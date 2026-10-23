package com.blackoutkit.vpn

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.File

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
class UpdatePlugin(private val appContext: Context) : MethodCallHandler {

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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

    /// Compares the archive's signing certificate with the installed app's.
    ///
    /// Returns an error message when they differ, null when they match (or
    /// when the platform will not tell us - older APIs report nothing, and
    /// Android's own signature enforcement remains the backstop there).
    /** Signature flags for this OS level: signingInfo is API 28+. */
    private fun signatureFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            android.content.pm.PackageManager.GET_SIGNATURES
        }

    /** Every signer digest on [info], newest API first, legacy as fallback. */
    @Suppress("DEPRECATION")
    private fun signerDigests(info: android.content.pm.PackageInfo): Set<String> {
        val modern = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
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
    private fun verifySameSigner(
        archive: android.content.pm.PackageInfo,
    ): String? {
        val installed = try {
            appContext.packageManager.getPackageInfo(appContext.packageName, signatureFlags())
        } catch (e: Exception) {
            return "Could not read this app's signature to compare against the " +
                "update (${e.message}). Nothing was installed."
        }

        val mine = signerDigests(installed)
        val theirs = signerDigests(archive)

        if (mine.isEmpty() || theirs.isEmpty()) {
            return "Could not read the signing certificate of the update or of the " +
                "installed app, so it cannot be verified. Nothing was installed."
        }
        if (mine.intersect(theirs).isEmpty()) {
            return "This update is signed with a different key than the app you " +
                "have installed, so Android cannot apply it in place. " +
                "Uninstalling the current app would erase your saved " +
                "configs - do that only if you are willing to re-import them."
        }
        return null
    }

    private fun certDigest(bytes: ByteArray): String {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        return md.digest(bytes).joinToString("") { "%02x".format(it) }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGS", "path is required", null)
            return
        }
        val file = File(path)
        if (!file.exists() || file.length() == 0L) {
            result.error("NOT_FOUND", "The downloaded APK is missing or empty ($path)", null)
            return
        }

        // A truncated download or a GitHub error page is not installable; say so
        // here instead of letting the installer report a parse failure.
        //
        // The flags matter: GET_SIGNING_CERTIFICATES is what makes the signer
        // available for the checks below.
        val archive = try {
            appContext.packageManager.getPackageArchiveInfo(path, signatureFlags())
        } catch (e: Exception) {
            null
        }
        if (archive == null) {
            result.error(
                "BAD_APK",
                "The downloaded file is not a valid APK (${file.length() / 1024} KB). " +
                    "Delete it and download again.",
                null,
            )
            return
        }

        // The file came off the network; the only thing that made it "ours" was
        // a matching size. Check that it is this app, and that it is signed by
        // the same key as the copy already installed. Android would refuse a
        // mismatched signature anyway, but only AFTER the user has been shown
        // an installer dialog - and a different package would be a plain
        // hijack, not an update.
        if (archive.packageName != appContext.packageName) {
            result.error(
                "WRONG_PACKAGE",
                "That file is not Blackout Kit (it is ${archive.packageName}). " +
                    "Nothing was installed.",
                null,
            )
            return
        }

        val signerCheck = verifySameSigner(archive)
        if (signerCheck != null) {
            result.error("SIGNER_MISMATCH", signerCheck, null)
            return
        }

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
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                appContext, "${appContext.packageName}.fileprovider", file
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                        or Intent.FLAG_ACTIVITY_NEW_TASK
                )
                // OEM installers read the grant from the clip data.
                .apply { clipData = ClipData.newRawUri("update", uri) }
            appContext.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
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
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:${appContext.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
        } catch (_: Exception) {
            try {
                appContext.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
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
