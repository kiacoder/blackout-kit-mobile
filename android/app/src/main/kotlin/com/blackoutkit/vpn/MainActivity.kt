package com.blackoutkit.vpn

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ProviderInfo
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.RemoteException
import android.util.Log
import androidx.core.content.IntentCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.IOException
import java.util.concurrent.atomic.AtomicReference

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val MAX_IMPORT_BYTES = 5L * 1024 * 1024

        private val pendingImport = AtomicReference<PendingImport?>(null)
    }

    // Avoid generated toString() methods for credential-bearing payloads.
    private sealed interface PendingImport {
        class Text(
            val value: String,
        ) : PendingImport

        class Document(
            val uri: Uri,
        ) : PendingImport
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The native tunnel bridge is not a pub package, so it is registered here
        // rather than by the generated plugin registrant.
        flutterEngine.plugins.add(VpnPlugin())

        // Host-side facts the Dart layer cannot get on its own: installed apps,
        // app icons, and Android's always-on VPN state.
        flutterEngine.plugins.add(NetworkPlugin())

        // In-app self-update: hands downloaded APKs to the package installer.
        UpdatePlugin(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
        UpdateConfirmation.attach(this)

        // Share / Open-with receive bridge: Gmail attachments ("Open with"),
        // shared links from the browser share sheet. Dart polls consumePending
        // on launch and on every app resume.
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger,
            "com.blackoutkit.vpn/intent",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePending" -> {
                    if (!removeObsoleteImportCopies(cacheDir)) {
                        Log.w(TAG, "Obsolete import cache cleanup incomplete")
                    }
                    val text =
                        when (val pending = pendingImport.getAndSet(null)) {
                            is PendingImport.Text -> pending.value
                            is PendingImport.Document -> readSharedText(pending.uri)
                            null -> null
                        }
                    result.success(text?.let { mapOf("type" to "text", "text" to it) })
                }
                else -> result.notImplemented()
            }
        }

        captureIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIntent(intent)
    }

    // / Reads the incoming intent into a Dart-ready payload. Shared TEXT goes
    // / through verbatim — a vless:// link contains '@', ':' and base64 '+'
    // / padding, so no second URI-decoding pass may touch it.
    private fun captureIntent(intent: Intent?) {
        if (intent == null) return
        val payload =
            when (intent.action) {
                Intent.ACTION_SEND -> {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    when {
                        !text.isNullOrBlank() && text.length <= MAX_IMPORT_BYTES ->
                            PendingImport.Text(text)
                        else -> {
                            val uri =
                                IntentCompat.getParcelableExtra(
                                    intent,
                                    Intent.EXTRA_STREAM,
                                    Uri::class.java,
                                )
                            uri?.let { PendingImport.Document(it) }
                        }
                    }
                }
                Intent.ACTION_VIEW -> {
                    val uri = intent.data
                    if (uri != null && uri.scheme.equals("content", ignoreCase = true)) {
                        // A content:// URI is NOT a filesystem path and is
                        // permission-scoped to this activity: it must be resolved
                        // through ContentResolver here, never passed to dart:io.
                        // file:// is rejected by isSafeImportUri below.
                        PendingImport.Document(uri)
                    } else {
                        null
                    }
                }
                else -> null
            } ?: return
        pendingImport.set(payload)
    }

    // Read while the provider grant is live. No credential-bearing cache file
    // is created; only a bounded UTF-8 string crosses the in-process channel.
    private fun readSharedText(uri: Uri?): String? {
        if (uri == null) return null
        return try {
            if (isSafeImportUri(uri)) readImport(uri) else null
        } catch (_: SecurityException) {
            Log.w(TAG, "Import provider access denied")
            null
        } catch (_: IllegalArgumentException) {
            Log.w(TAG, "Import provider rejected the document")
            null
        } catch (_: RemoteException) {
            Log.w(TAG, "Import provider disconnected")
            null
        } catch (_: IOException) {
            Log.w(TAG, "Import document could not be read")
            null
        }
    }

    private fun readImport(uri: Uri): String? {
        val client = contentResolver.acquireUnstableContentProviderClient(uri) ?: return null
        return try {
            val pfd = client.openFile(uri, "r")
            if (pfd == null) {
                null
            } else {
                ParcelFileDescriptor.AutoCloseInputStream(pfd).use { readBoundedImportText(it, MAX_IMPORT_BYTES) }
            }
        } finally {
            // close() is available from API 24, our minimum supported SDK.
            client.close()
        }
    }

    // The integer overload is required only on Android 7–12L.
    @Suppress("DEPRECATION")
    private fun resolveImportProvider(authority: String): ProviderInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.resolveContentProvider(authority, PackageManager.ComponentInfoFlags.of(0))
        } else {
            packageManager.resolveContentProvider(authority, 0)
        }

    // Require a real URI-specific grant, not just general provider access.
    // Reject providers running under our own UID, including alternate authorities.
    private fun isSafeImportUri(uri: Uri): Boolean {
        val authority = uri.authority
        val provider =
            if (authority != null && uri.scheme.equals("content", ignoreCase = true) && '@' !in authority) {
                resolveImportProvider(authority)
            } else {
                null
            }
        return provider != null &&
            provider.applicationInfo.uid != Process.myUid() &&
            checkUriPermission(
                uri,
                Process.myPid(),
                Process.myUid(),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            ) == PackageManager.PERMISSION_GRANTED
    }
}
