package com.blackoutkit.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges `com.blackoutkit.vpn/service` to [BlackoutVpnService].
 *
 * connect() resolves only after establish() has genuinely succeeded or failed,
 * so Dart never reports "connected" while the tunnel is still coming up.
 */
class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    private var pendingPrepare: MethodChannel.Result? = null
    private var pendingConnect: MethodChannel.Result? = null

    private val main = Handler(Looper.getMainLooper())

    companion object {
        private const val TAG = "VpnPlugin"
        private const val CHANNEL = "com.blackoutkit.vpn/service"
        private const val PREPARE_REQUEST = 0xB10C
        private const val CONNECT_TIMEOUT_MS = 20_000L
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        BlackoutVpnService.statusListener = { status ->
            main.post { channel?.invokeMethod("onStatusChanged", mapOf("status" to status)) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BlackoutVpnService.statusListener = null
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> handlePrepare(result)
            "connect" -> handleConnect(call, result)
            "disconnect" -> handleDisconnect(result)
            "isRunning" -> result.success(BlackoutVpnService.isRunning)
            "getStatus" -> result.success(statusMap())
            "getConnectedIP" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "isConnected" to BlackoutVpnService.isRunning,
        "isRunning" to BlackoutVpnService.isRunning,
        "error" to BlackoutVpnService.lastError
    )

    private fun handlePrepare(result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }

        // Null means consent was already granted for this app.
        val consent = VpnService.prepare(ctx)
        if (consent == null) {
            result.success(true)
            return
        }

        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "VPN consent needs a foreground Activity", null)
            return
        }

        pendingPrepare = result
        act.startActivityForResult(consent, PREPARE_REQUEST)
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }
        if (VpnService.prepare(ctx) != null) {
            result.error("NOT_PREPARED", "VPN consent has not been granted - call prepare() first", null)
            return
        }
        if (pendingConnect != null) {
            result.error("BUSY", "A connect attempt is already in flight", null)
            return
        }

        pendingConnect = result
        BlackoutVpnService.connectResultCallback = { ok -> resolveConnect(ok) }

        val intent = Intent(ctx, BlackoutVpnService::class.java).apply {
            action = BlackoutVpnService.ACTION_CONNECT
            putExtra(BlackoutVpnService.EXTRA_PROTOCOL, call.argument<String>("protocol"))
            putExtra(BlackoutVpnService.EXTRA_DISPLAY_NAME, call.argument<String>("displayName"))
            putExtra(
                BlackoutVpnService.EXTRA_SOCKS_PORT,
                call.argument<Int>("socksPort") ?: BlackoutVpnService.DEFAULT_SOCKS_PORT
            )
            putExtra(BlackoutVpnService.EXTRA_DNS, call.argument<String>("dns"))
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_ALLOWED_APPS,
                ArrayList(call.argument<List<String>>("allowedApps") ?: emptyList())
            )
            putStringArrayListExtra(
                BlackoutVpnService.EXTRA_DISALLOWED_APPS,
                ArrayList(call.argument<List<String>>("disallowedApps") ?: emptyList())
            )
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        } catch (e: Exception) {
            resolveConnect(false, "Could not start the VPN service: ${e.message}")
            return
        }

        main.postDelayed({
            if (pendingConnect != null) {
                resolveConnect(false, "Timed out waiting for the tunnel to come up")
            }
        }, CONNECT_TIMEOUT_MS)
    }

    private fun resolveConnect(ok: Boolean, message: String? = null) {
        val result = pendingConnect ?: return
        pendingConnect = null
        BlackoutVpnService.connectResultCallback = null

        if (ok) {
            result.success(true)
        } else {
            val reason = message
                ?: BlackoutVpnService.lastError
                ?: "The tunnel failed to come up"
            Log.w(TAG, "connect failed: $reason")
            result.error("CONNECT_FAILED", reason, null)
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }
        try {
            ctx.startService(
                Intent(ctx, BlackoutVpnService::class.java).apply {
                    action = BlackoutVpnService.ACTION_DISCONNECT
                }
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCONNECT_FAILED", e.message, null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            if (requestCode == PREPARE_REQUEST) {
                pendingPrepare?.success(resultCode == Activity.RESULT_OK)
                pendingPrepare = null
                true
            } else {
                false
            }
        }
    }

    override fun onDetachedFromActivity() {
        activity = null
        pendingPrepare?.success(false)
        pendingPrepare = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
