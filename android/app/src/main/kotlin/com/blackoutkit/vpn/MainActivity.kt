package com.blackoutkit.vpn

import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.core.content.IntentCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        // Payload waiting for Dart: set on cold start (onCreate intent) and on
        // warm start (onNewIntent), consumed exactly once by the Dart side.
        // A static holder is the only way to bridge the gap where the engine
        // is not yet running during a cold start.
        @Volatile
        var pendingPayload: Map<String, String>? = null
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

        // Share / Open-with receive bridge: Gmail attachments ("Open with"),
        // shared links from the browser share sheet. Dart polls consumePending
        // on launch and on every app resume.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.blackoutkit.vpn/intent",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePending" -> {
                    val payload = pendingPayload
                    pendingPayload = null
                    result.success(payload)
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

    /// Reads the incoming intent into a Dart-ready payload. Shared TEXT goes
    /// through verbatim — a vless:// link contains '@', ':' and base64 '+'
    /// padding, so no second URI-decoding pass may touch it.
    private fun captureIntent(intent: Intent?) {
        if (intent == null) return
        val payload = when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                when {
                    !text.isNullOrBlank() ->
                        mapOf("type" to "text", "text" to text)
                    else -> {
                        val uri = IntentCompat.getParcelableExtra(
                            intent, Intent.EXTRA_STREAM, Uri::class.java
                        )
                        copyToCache(uri)?.let { mapOf("type" to "file", "path" to it) }
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
                    copyToCache(uri)?.let { mapOf("type" to "file", "path" to it) }
                } else {
                    null
                }
            }
            else -> null
        } ?: return
        pendingPayload = payload
    }

    /// Copies a picked/received document into our own cache dir and returns
    /// the real path. Content-provider grants can expire after a process
    /// restart, so the copy must happen while the grant is live.
    ///
    /// Resolution goes through a [ContentProviderClient] rather than
    /// `ContentResolver.openInputStream`: the client pins the remote provider
    /// for the whole copy (no mid-copy provider death), and the read still
    /// fails closed under the sender's grant scoping.
    private fun copyToCache(uri: Uri?): String? {
        if (uri == null || !isSafeImportUri(uri)) return null
        val client = contentResolver.acquireUnstableContentProviderClient(uri)
            ?: return null
        return try {
            val pfd = client.openFile(uri, "r") ?: return null
            val file = File(cacheDir, "import-${System.currentTimeMillis()}.cfg")
            ParcelFileDescriptor.AutoCloseInputStream(pfd).use { source ->
                file.outputStream().use { source.copyTo(it) }
            }
            if (file.length() > 5L * 1024 * 1024) {
                file.delete()
                null
            } else {
                file.absolutePath
            }
        } catch (e: Exception) {
            null
        } finally {
            client.release()
        }
    }

    /// CodeQL High #20 — the URI comes from an external intent, so a hostile
    /// sender controls it completely. Two hard rules before any resolution:
    ///
    /// 1. `file://` is rejected: it is a raw filesystem path, and copying it
    ///    into the import cache would turn a share-sheet tap into an
    ///    arbitrary-file reader (the copied file's path is surfaced to Dart).
    /// 2. Our own package's authorities are rejected: a crafted self-URI
    ///    could copy engine state through the import path.
    ///
    /// Everything else must be a `content://` URI covered by the sender's
    /// FLAG_GRANT_READ_URI_PERMISSION, which is scoped to that exact URI —
    /// cross-app reads fail closed at the resolver.
    private fun isSafeImportUri(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase()
        if (scheme == "file") return false
        if (scheme != "content") return false
        val authority = uri.authority ?: return false
        if (authority.equals(packageName, ignoreCase = true)) return false
        return true
    }
}
