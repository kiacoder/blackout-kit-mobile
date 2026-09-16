package com.blackoutkit.vpn

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * Split Tunneling Service - Route specific apps through VPN, others direct
 *
 * Strategy:
 * 1. Get UID (user id) of installed apps
 * 2. Use iptables to route traffic by UID through VPN
 * 3. Support whitelist, blacklist, and smart modes
 *
 * Note: Requires root access for iptables manipulation
 */
class SplitTunnelingService(private val context: Context) {
    companion object {
        private const val TAG = "SplitTunnel"
        private const val CHANNEL = "com.blackoutkit.vpn/splittunneling"
    }

    private var channel: MethodChannel? = null
    private var isActive = false
    private var currentMode = "whitelist"
    private val scope = CoroutineScope(Dispatchers.IO + Job())
    private val selectedApps = mutableSetOf<String>()

    fun setupChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> handleGetInstalledApps(result)
                "enableSplitTunneling" -> {
                    val mode = call.argument<String>("mode") ?: "whitelist"
                    handleEnableSplitTunneling(mode, result)
                }
                "disableSplitTunneling" -> handleDisableSplitTunneling(result)
                "addAppToTunnel" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    handleAddAppToTunnel(packageName, result)
                }
                "removeAppFromTunnel" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    handleRemoveAppFromTunnel(packageName, result)
                }
                "activateSplitTunneling" -> {
                    val apps = call.argument<List<String>>("apps") ?: emptyList()
                    handleActivateSplitTunneling(apps, result)
                }
                "deactivateSplitTunneling" -> handleDeactivateSplitTunneling(result)
                "changeSplitTunnelingMode" -> {
                    val mode = call.argument<String>("mode") ?: "whitelist"
                    handleChangeMode(mode, result)
                }
                "getSplitTunnelingConfig" -> handleGetConfiguration(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleGetInstalledApps(result: MethodChannel.Result) {
        scope.launch {
            try {
                val apps = mutableListOf<Map<String, Any>>()
                val packageManager = context.packageManager

                val installedPackages = packageManager.getInstalledApplications(0)
                for (appInfo in installedPackages) {
                    val appName = packageManager.getApplicationLabel(appInfo).toString()
                    apps.add(
                        mapOf(
                            "packageName" to appInfo.packageName,
                            "appName" to appName,
                            "iconPath" to null,
                            "includedInTunnel" to false
                        )
                    )
                }

                Log.i(TAG, "Found ${apps.size} installed apps")
                result.success(apps)
            } catch (e: Exception) {
                Log.e(TAG, "Error getting installed apps: ${e.message}")
                result.error("GET_APPS_FAILED", e.message, null)
            }
        }
    }

    private fun handleEnableSplitTunneling(mode: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                if (checkRootAccess()) {
                    currentMode = mode
                    Log.i(TAG, "Split tunneling enabled ($mode mode)")
                    result.success(true)
                } else {
                    Log.w(TAG, "No root access - split tunneling unavailable")
                    result.success(false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error enabling split tunneling: ${e.message}")
                result.error("ENABLE_FAILED", e.message, null)
            }
        }
    }

    private fun handleDisableSplitTunneling(result: MethodChannel.Result) {
        scope.launch {
            try {
                if (isActive) {
                    deactivateSplitTunneling()
                    isActive = false
                }
                selectedApps.clear()
                Log.i(TAG, "Split tunneling disabled")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error disabling split tunneling: ${e.message}")
                result.error("DISABLE_FAILED", e.message, null)
            }
        }
    }

    private fun handleAddAppToTunnel(packageName: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                selectedApps.add(packageName)

                if (isActive) {
                    val uid = getAppUID(packageName)
                    if (uid > 0) {
                        activateForApp(uid)
                    }
                }

                Log.i(TAG, "App added to tunnel: $packageName")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error adding app: ${e.message}")
                result.error("ADD_APP_FAILED", e.message, null)
            }
        }
    }

    private fun handleRemoveAppFromTunnel(packageName: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                selectedApps.remove(packageName)

                if (isActive) {
                    val uid = getAppUID(packageName)
                    if (uid > 0) {
                        deactivateForApp(uid)
                    }
                }

                Log.i(TAG, "App removed from tunnel: $packageName")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing app: ${e.message}")
                result.error("REMOVE_APP_FAILED", e.message, null)
            }
        }
    }

    private fun handleActivateSplitTunneling(
        apps: List<String>,
        result: MethodChannel.Result
    ) {
        scope.launch {
            try {
                selectedApps.clear()
                selectedApps.addAll(apps)

                activateSplitTunneling()
                isActive = true

                Log.i(TAG, "Split tunneling activated for ${apps.size} apps")
                result.success(null)
            } catch (e: Exception) {
                Log.e(TAG, "Error activating split tunneling: ${e.message}")
                result.error("ACTIVATE_FAILED", e.message, null)
            }
        }
    }

    private fun handleDeactivateSplitTunneling(result: MethodChannel.Result) {
        scope.launch {
            try {
                if (isActive) {
                    deactivateSplitTunneling()
                    isActive = false
                }
                Log.i(TAG, "Split tunneling deactivated")
                result.success(null)
            } catch (e: Exception) {
                Log.e(TAG, "Error deactivating split tunneling: ${e.message}")
                result.error("DEACTIVATE_FAILED", e.message, null)
            }
        }
    }

    private fun handleChangeMode(newMode: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                currentMode = newMode
                if (isActive) {
                    deactivateSplitTunneling()
                    activateSplitTunneling()
                }
                Log.i(TAG, "Mode changed to: $newMode")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error changing mode: ${e.message}")
                result.error("CHANGE_MODE_FAILED", e.message, null)
            }
        }
    }

    private fun handleGetConfiguration(result: MethodChannel.Result) {
        val config = mapOf(
            "enabled" to true,
            "active" to isActive,
            "mode" to currentMode,
            "appCount" to selectedApps.size
        )
        result.success(config)
    }

    /**
     * Activate split tunneling rules via iptables
     * Routes selected apps through VPN based on their UID
     */
    private suspend fun activateSplitTunneling() = withContext(Dispatchers.IO) {
        try {
            selectedApps.forEach { packageName ->
                val uid = getAppUID(packageName)
                if (uid > 0) {
                    activateForApp(uid)
                }
            }

            Log.i(TAG, "Split tunneling iptables rules activated")
        } catch (e: Exception) {
            Log.e(TAG, "Error activating split tunneling: ${e.message}")
            throw e
        }
    }

    /**
     * Activate split tunneling for a specific app UID
     * Whitelis mode: route only this UID through VPN
     */
    private suspend fun activateForApp(uid: Int) = withContext(Dispatchers.IO) {
        when (currentMode) {
            "whitelist" -> {
                // Route this UID to VPN (tun0)
                executeCommand("iptables -A OUTPUT -m owner --uid-owner $uid -o tun0 -j ACCEPT")
                executeCommand("iptables -A OUTPUT -m owner --uid-owner $uid -o any -j REJECT")
            }
            "blacklist" -> {
                // Route this UID through direct connection (not VPN)
                executeCommand("iptables -A OUTPUT -m owner --uid-owner $uid -o ! tun0 -j ACCEPT")
            }
        }
    }

    /**
     * Deactivate split tunneling rules via iptables
     */
    private suspend fun deactivateSplitTunneling() = withContext(Dispatchers.IO) {
        try {
            selectedApps.forEach { packageName ->
                val uid = getAppUID(packageName)
                if (uid > 0) {
                    deactivateForApp(uid)
                }
            }

            // Clear all UID-based rules
            executeCommand("iptables -F OUTPUT")

            Log.i(TAG, "Split tunneling iptables rules deactivated")
        } catch (e: Exception) {
            Log.e(TAG, "Error deactivating split tunneling: ${e.message}")
            throw e
        }
    }

    /**
     * Deactivate split tunneling for a specific app UID
     */
    private suspend fun deactivateForApp(uid: Int) = withContext(Dispatchers.IO) {
        when (currentMode) {
            "whitelist" -> {
                executeCommand("iptables -D OUTPUT -m owner --uid-owner $uid -o tun0 -j ACCEPT")
                executeCommand("iptables -D OUTPUT -m owner --uid-owner $uid -o any -j REJECT")
            }
            "blacklist" -> {
                executeCommand("iptables -D OUTPUT -m owner --uid-owner $uid -o ! tun0 -j ACCEPT")
            }
        }
    }

    /**
     * Get UID of app by package name
     */
    private fun getAppUID(packageName: String): Int {
        return try {
            val appInfo = context.packageManager.getApplicationInfo(packageName, 0)
            appInfo.uid
        } catch (e: Exception) {
            Log.w(TAG, "Could not get UID for $packageName: ${e.message}")
            -1
        }
    }

    /**
     * Execute iptables command via su (requires root)
     */
    private suspend fun executeCommand(command: String): String = withContext(Dispatchers.IO) {
        try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            val exitCode = process.waitFor()

            if (exitCode != 0) {
                val error = process.errorStream.bufferedReader().readText()
                Log.w(TAG, "Command failed: $command - $error")
            }

            process.inputStream.bufferedReader().readText()
        } catch (e: Exception) {
            Log.e(TAG, "Error executing command: $command - ${e.message}")
            throw e
        }
    }

    /**
     * Check if root access is available
     */
    private suspend fun checkRootAccess(): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            val process = Runtime.getRuntime().exec("su -c 'echo success'")
            val output = process.inputStream.bufferedReader().readLine() ?: ""
            process.waitFor()
            output.contains("success")
        } catch (e: Exception) {
            Log.d(TAG, "Root check failed: ${e.message}")
            false
        }
    }

    fun cleanup() {
        scope.cancel()
    }
}
