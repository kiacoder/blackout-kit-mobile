package com.blackoutkit.vpn

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.security.MessageDigest

private const val BYTES_PER_KIB = 1024L

/**
 * In-app self-update: hands a downloaded APK to Android's package installer.
 *
 * The APK is downloaded by the Dart layer into the app's internal files dir
 * (`filesDir/updates/`), which [FileProvider] exposes through
 * `res/xml/file_paths.xml`. Internal storage is used deliberately: the external
 * app dir is not always the volume FileProvider maps, and `getUriForFile` then
 * throws "Failed to find configured root".
 *
 * Two things Android will silently refuse without help:
 *
 *  - Android 8+ requires the per-app "install unknown apps" grant. Without it
 *    the installer intent goes nowhere (or dumps the user in Settings), so this
 *    checks [canRequestPackageInstalls] first and sends them to the exact
 *    toggle for this app instead of failing with a blank screen.
 *  - The install intent must carry the URI in a [ClipData] as well as the
 *    grant flag: several OEM installers (Samsung, Xiaomi, Huawei) read the
 *    clip data and otherwise throw SecurityException on the content URI.
 *
 * The APK is also validated with [android.content.pm.PackageManager.getPackageArchiveInfo]
 * before launching, so a truncated download or an HTML error page surfaces as
 * "the download is not a valid APK" rather than the installer's opaque
 * "problem parsing the package".
 */
class UpdatePlugin(
    private val appContext: Context,
) : MethodCallHandler {
    private val signerVerifier = ApkSignerVerifier(appContext)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        // Hash large APKs and inspect signing metadata off the UI thread.
        val channel =
            MethodChannel(messenger, CHANNEL, StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "installApk" -> installApk(call, result)
            // Which release asset fits this device. A 32-bit phone cannot
            // install the arm64 APK (INSTALL_FAILED_NO_MATCHING_ABIS), so the
            // download must pick by ABI instead of assuming arm64.
            "deviceAbi" -> result.success(primaryAbi())
            "canInstallPackages" -> result.success(canInstallPackages())
            else -> result.notImplemented()
        }
    }

    private fun installApk(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val tag = call.argument<String>("tag")
        if (tag == null || !UpdateArchivePolicy.validTag(tag)) {
            result.error("INVALID_ARGS", "A valid release tag is required", null)
            return
        }
        val root = File(appContext.filesDir, "updates")
        val file = UpdateArchivePolicy.resolveRelease(root, tag)
        if (file == null) {
            result.error("BAD_APK_PATH", "The update must be a nonempty APK in private update storage.", null)
            return
        }

        val expectedBytes = call.argument<Number>("size")?.toLong()
        val expectedDigest = call.argument<String>("digest")
        if (expectedBytes == null ||
            expectedDigest == null ||
            !UpdateArchivePolicy.matchesDigest(file, expectedBytes, expectedDigest)
        ) {
            result.error("BAD_APK_DIGEST", "The update failed native integrity verification.", null)
        } else if (validateArchive(file, tag, result)) {
            // Installer and permission UI must be launched on the main thread.
            mainHandler.post {
                if (requireInstallPermission(result)) launchInstaller(file, result)
            }
        }
    }

    private fun validateArchive(
        file: File,
        tag: String,
        result: MethodChannel.Result,
    ): Boolean {
        // A truncated download or a GitHub error page is not installable; say so
        // here instead of letting the installer report a parse failure.
        //
        // The flags matter: GET_SIGNING_CERTIFICATES is what makes the signer
        // available for the checks below.
        val archive =
            try {
                signerVerifier.archiveInfo(file)
            } catch (_: IllegalArgumentException) {
                Log.w(CHANNEL, "APK archive parser rejected input")
                null
            } catch (_: SecurityException) {
                Log.w(CHANNEL, "APK archive access denied")
                null
            }
        if (archive == null) {
            result.error(
                "BAD_APK",
                "The downloaded file is not a valid APK (${file.length() / BYTES_PER_KIB} KB). " +
                    "Delete it and download again.",
                null,
            )
            return false
        }

        // The file came off the network; the only thing that made it "ours" was
        // a matching size. Check that it is this app, and that it is signed by
        // the same key as the copy already installed. Android would refuse a
        // mismatched signature anyway, but only AFTER the user has been shown
        // an installer dialog - and a different package would be a plain
        // hijack, not an update.
        return if (archive.packageName != appContext.packageName) {
            result.error(
                "WRONG_PACKAGE",
                "That file is not Blackout Kit (it is ${archive.packageName}). " +
                    "Nothing was installed.",
                null,
            )
            false
        } else if (archive.versionName != tag.removePrefix("v")) {
            result.error("WRONG_VERSION", "APK version does not match the requested release.", null)
            false
        } else {
            val signerCheck = signerVerifier.verifySameSigner(archive)
            if (signerCheck != null) result.error("SIGNER_MISMATCH", signerCheck, null)
            signerCheck == null
        }
    }

    private fun requireInstallPermission(result: MethodChannel.Result): Boolean {
        if (!canInstallPackages()) {
            // Send the user straight to this app's toggle, then let them retry.
            openUnknownSourcesSettings()
            result.error(
                "ALLOW_UNKNOWN_SOURCES",
                "Android needs permission to install updates from Blackout Kit. " +
                    "Turn on \"Allow from this source\" on the screen that just opened, " +
                    "then tap Update again.",
                null,
            )
            return false
        }
        return true
    }

    private fun launchInstaller(
        file: File,
        result: MethodChannel.Result,
    ) {
        try {
            val uri =
                FileProvider.getUriForFile(
                    appContext,
                    "${appContext.packageName}.fileprovider",
                    file,
                )
            val intent =
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                            or Intent.FLAG_ACTIVITY_NEW_TASK,
                    )
                    // OEM installers read the grant from the clip data.
                    .apply { clipData = ClipData.newRawUri("update", uri) }
            appContext.startActivity(intent)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("INSTALL_FAILED", e.message ?: e.toString(), null)
        } catch (e: SecurityException) {
            result.error("INSTALL_FAILED", e.message ?: e.toString(), null)
        } catch (e: IllegalArgumentException) {
            result.error("INSTALL_FAILED", e.message ?: e.toString(), null)
        }
    }

    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            appContext.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openUnknownSourcesSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val intent =
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData("package:${appContext.packageName}".toUri())
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
        } catch (_: Exception) {
            try {
                appContext.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (_: Exception) {
                // Nothing else to try; the Dart layer already reports the reason.
            }
        }
    }

    private fun primaryAbi(): String {
        val abis = Build.SUPPORTED_ABIS
        return when {
            abis.contains("arm64-v8a") -> "arm64-v8a"
            abis.contains("armeabi-v7a") -> "armeabi-v7a"
            abis.isNotEmpty() -> abis[0]
            else -> "arm64-v8a"
        }
    }

    companion object {
        const val CHANNEL = "com.blackoutkit.vpn/update"
    }
}

/** APK signer verification is independent of launching the installer. */
private class ApkSignerVerifier(
    private val appContext: Context,
) {
    /** Signature flags for this OS level: signingInfo is API 28+. */
    fun signatureFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            android.content.pm.PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    fun archiveInfo(file: File): android.content.pm.PackageInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.PackageInfoFlags.of(signatureFlags().toLong()),
            )
        } else {
            appContext.packageManager.getPackageArchiveInfo(file.absolutePath, signatureFlags())
        }

    @Suppress("DEPRECATION")
    private fun installedInfo(): android.content.pm.PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.packageManager.getPackageInfo(
                appContext.packageName,
                PackageManager.PackageInfoFlags.of(signatureFlags().toLong()),
            )
        } else {
            appContext.packageManager.getPackageInfo(appContext.packageName, signatureFlags())
        }

    /** Every signer digest on [info], newest API first, legacy as fallback. */
    @Suppress("DEPRECATION")
    private fun signerDigests(info: android.content.pm.PackageInfo): Set<String> {
        val modern =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.signingInfo?.apkContentsSigners?.map { certDigest(it.toByteArray()) }
            } else {
                null
            }
        val legacy = info.signatures?.map { certDigest(it.toByteArray()) }
        return (modern ?: legacy).orEmpty().toSet()
    }

    /**
     * Compares the downloaded APK's signer with the installed app's.
     *
     * Returns null when they match, or the reason to refuse.
     *
     * This FAILS CLOSED. It used to return null - meaning "fine, proceed" -
     * whenever either side's certificates were unavailable, and also on any
     * exception. That turned the check into a no-op on API 24-27 (where
     * `signingInfo` does not exist) and on any device where the lookup threw.
     */
    fun verifySameSigner(archive: android.content.pm.PackageInfo): String? {
        val installed =
            try {
                installedInfo()
            } catch (_: PackageManager.NameNotFoundException) {
                null
            } catch (_: SecurityException) {
                null
            } ?: return "Could not read this app's signature. Nothing was installed."

        val mine = signerDigests(installed)
        val theirs = signerDigests(archive)

        return when {
            mine.isEmpty() || theirs.isEmpty() ->
                "Could not read the signing certificate of the update or of the " +
                    "installed app, so it cannot be verified. Nothing was installed."
            !UpdateArchivePolicy.sameSigners(mine, theirs) ->
                "This update is signed with a different key than the app you " +
                    "have installed, so Android cannot apply it in place. " +
                    "Keep your existing app and contact support."
            else -> null
        }
    }

    private fun certDigest(bytes: ByteArray): String {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        return md.digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

/** Narrow policy for files passed to the package installer. */
internal object UpdateArchivePolicy {
    private const val MAX_TAG_LENGTH = 64
    private const val MIN_APK_BYTES = 1024L * 1024
    private const val MAX_APK_BYTES = 256L * 1024 * 1024
    private val releaseTag = Regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+(?:-beta\\.[0-9]+)?$")
    private val sha256Pattern = Regex("^sha256:[a-f0-9]{64}$")

    fun validTag(tag: String): Boolean = tag.length <= MAX_TAG_LENGTH && releaseTag.matches(tag)

    fun matchesDigest(
        file: File,
        expectedBytes: Long,
        expectedDigest: String,
    ): Boolean {
        if (expectedBytes !in MIN_APK_BYTES..MAX_APK_BYTES ||
            !sha256Pattern.matches(expectedDigest) ||
            file.length() != expectedBytes
        ) {
            return false
        }
        return try {
            readDigest(file, expectedBytes) == expectedDigest && file.length() == expectedBytes
        } catch (_: java.io.IOException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun readDigest(
        file: File,
        expectedBytes: Long,
    ): String? {
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        var count: Int
        file.inputStream().use { input ->
            count = input.read(buffer)
            while (count > 0 && total <= expectedBytes) {
                total += count
                hash.update(buffer, 0, count)
                count = input.read(buffer)
            }
        }
        return if (total == expectedBytes && count == -1) {
            "sha256:" + hash.digest().joinToString("") { "%02x".format(it) }
        } else {
            null
        }
    }

    fun resolveRelease(
        root: File,
        tag: String,
    ): File? =
        if (validTag(tag)) {
            resolve(root, File(root, "blackout-$tag.apk"))
        } else {
            null
        }

    fun resolve(
        root: File,
        candidate: File,
    ): File? =
        try {
            val directory = root.canonicalFile
            val file = candidate.canonicalFile
            file.takeIf {
                directory == File(root.parentFile?.canonicalFile, root.name) &&
                    candidate.absoluteFile.parentFile in setOf(root.absoluteFile, directory) &&
                    file == File(directory, candidate.name) &&
                    file.extension == "apk" &&
                    file.isFile &&
                    file.length() > 0L
            }
        } catch (_: java.io.IOException) {
            null
        } catch (_: SecurityException) {
            null
        }

    fun sameSigners(
        installed: Set<String>,
        archive: Set<String>,
    ): Boolean = installed.isNotEmpty() && installed == archive
}
