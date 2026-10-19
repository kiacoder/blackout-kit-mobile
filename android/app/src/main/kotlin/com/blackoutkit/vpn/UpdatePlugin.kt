package com.blackoutkit.vpn

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.io.File

/**
 * In-app self-update: hands a downloaded APK to Android's package installer.
 *
 * The APK is downloaded by the Dart layer into the app-specific external
 * files dir (`.../files/updates/`), which [FileProvider] exposes through
 * `res/xml/file_paths.xml`. Requires REQUEST_INSTALL_PACKAGES (manifest);
 * Android shows its own "install this app?" confirmation.
 */
class UpdatePlugin(private val appContext: Context) : MethodCallHandler {

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "path is required", null)
                    return
                }
                val file = File(path)
                if (!file.exists()) {
                    result.error("NOT_FOUND", "APK not found at $path", null)
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
                    appContext.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.blackoutkit.vpn/update"
    }
}
