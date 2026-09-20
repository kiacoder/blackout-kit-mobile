package com.blackoutkit.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Bridges `com.blackoutkit.vpn/network` — the host-side facts the Dart layer
 * cannot obtain on its own.
 *
 * Three things live here, and nothing else:
 *
 *  - the installed-app list, for the split-tunneling picker
 *  - per-app icons, fetched lazily so listing 200 apps does not cost 200 icons
 *  - the real state of Android's own kill switch (always-on VPN + lockdown),
 *    which is the part a non-root app genuinely cannot implement itself
 */
class NetworkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var context: Context? = null

    companion object {
        private const val TAG = "NetworkPlugin"
        private const val CHANNEL = "com.blackoutkit.vpn/network"

        // Settings.Secure keys. Referenced as literals because the matching
        // Settings.Secure constants are @hide and would not compile.
        private const val KEY_ALWAYS_ON_VPN_APP = "always_on_vpn_app"
        private const val KEY_ALWAYS_ON_VPN_LOCKDOWN = "always_on_vpn_lockdown"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> handleGetInstalledApps(call, result)
            "getAppIcon" -> handleGetAppIcon(call, result)
            "getKillSwitchState" -> result.success(killSwitchState())
            "openVpnSettings" -> handleOpenVpnSettings(result)
            else -> result.notImplemented()
        }
    }

    // ───────────────────────── installed apps ──────────────────────────────

    private fun handleGetInstalledApps(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }

        val includeSystem = call.argument<Boolean>("includeSystem") ?: false

        try {
            val pm = ctx.packageManager
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)

            val payload = ArrayList<Map<String, Any?>>()
            for (info in apps) {
                val isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                if (isSystem && !includeSystem) continue

                // An app with no launcher entry is not something a user can
                // meaningfully route, so skip it.
                if (pm.getLaunchIntentForPackage(info.packageName) == null) continue

                payload.add(
                    mapOf(
                        "packageName" to info.packageName,
                        "appName" to pm.getApplicationLabel(info).toString(),
                        "isSystem" to isSystem
                    )
                )
            }

            payload.sortBy { it["appName"]?.toString()?.lowercase() }
            result.success(payload)
        } catch (t: Throwable) {
            Log.e(TAG, "could not list installed apps", t)
            result.error("LIST_FAILED", t.message, null)
        }
    }

    /**
     * Icons are fetched one at a time on demand. Encoding every icon up front
     * would mean tens of megabytes of base64 crossing the channel to render a
     * list the user has not scrolled yet.
     */
    private fun handleGetAppIcon(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        val packageName = call.argument<String>("packageName")
        if (ctx == null || packageName.isNullOrBlank()) {
            result.success(null)
            return
        }

        try {
            val drawable = ctx.packageManager.getApplicationIcon(packageName)
            val bitmap = drawable.toBitmap(96)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            result.success(
                Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
            )
        } catch (t: Throwable) {
            Log.w(TAG, "no icon for $packageName: ${t.message}")
            result.success(null)
        }
    }

    private fun Drawable.toBitmap(sizePx: Int): Bitmap {
        if (this is BitmapDrawable && bitmap != null) {
            return Bitmap.createScaledBitmap(bitmap, sizePx, sizePx, true)
        }
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        setBounds(0, 0, sizePx, sizePx)
        draw(canvas)
        return bitmap
    }

    // ───────────────────────── kill switch state ───────────────────────────

    /**
     * Reports Android's own always-on VPN configuration.
     *
     * This is the honest answer to "is there a real kill switch on this
     * device": only the system can block traffic when the tunnel is down, and
     * only if the user turned it on. An app cannot grant itself this.
     */
    private fun killSwitchState(): Map<String, Any?> {
        val ctx = context ?: return mapOf("supported" to false)
        val resolver = ctx.contentResolver

        val alwaysOnApp = try {
            Settings.Secure.getString(resolver, KEY_ALWAYS_ON_VPN_APP)
        } catch (t: Throwable) {
            null
        }
        val lockdown = try {
            Settings.Secure.getString(resolver, KEY_ALWAYS_ON_VPN_LOCKDOWN)
        } catch (t: Throwable) {
            null
        }

        val isUs = alwaysOnApp != null && alwaysOnApp == ctx.packageName
        val lockdownOn = lockdown == "1"

        return mapOf(
            "supported" to true,
            "alwaysOnPackage" to alwaysOnApp,
            "isAlwaysOnForThisApp" to isUs,
            "lockdownEnabled" to lockdownOn,
            // The combination that actually blocks traffic on tunnel loss.
            "systemKillSwitchActive" to (isUs && lockdownOn),
            "inAppKillSwitchAvailable" to true,
            "requiresUserAction" to !(isUs && lockdownOn)
        )
    }

    /**
     * Deep-links to the system VPN screen so the user can enable always-on VPN
     * and "Block connections without VPN". There is no API to set these.
     */
    private fun handleOpenVpnSettings(result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin is not attached to a Flutter engine", null)
            return
        }

        val intents = listOf(
            Intent(Settings.ACTION_VPN_SETTINGS),
            Intent("android.net.vpn.SETTINGS"),
            Intent(Settings.ACTION_SETTINGS)
        )

        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                ctx.startActivity(intent)
                result.success(true)
                return
            } catch (t: Throwable) {
                Log.w(TAG, "could not open $intent: ${t.message}")
            }
        }

        // Last resort: dump the user at the top of system settings.
        try {
            ctx.startActivity(
                Intent(Settings.ACTION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            result.success(true)
        } catch (t: Throwable) {
            result.error("SETTINGS_FAILED", t.message, null)
        }
    }
}
