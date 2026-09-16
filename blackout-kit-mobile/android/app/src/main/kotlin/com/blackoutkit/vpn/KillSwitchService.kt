package com.blackoutkit.vpn

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * Kill Switch Service - Blocks all non-VPN traffic using iptables
 *
 * Strategy:
 * 1. Get VPN tunnel interface (tun0, tun1, etc.)
 * 2. Use iptables to block all traffic except through VPN
 * 3. Fall back to system settings if root access unavailable
 *
 * Note: Requires either:
 * - Root access (iptables via su)
 * - Android 10+ (VPN interface metadata via ConnectivityManager)
 */
class KillSwitchService(private val context: Context) {
    companion object {
        private const val TAG = "KillSwitch"
        private const val CHANNEL = "com.blackoutkit.vpn/killswitch"
    }

    private var channel: MethodChannel? = null
    private var isActive = false
    private val scope = CoroutineScope(Dispatchers.IO + Job())

    fun setupChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableKillSwitch" -> handleEnableKillSwitch(result)
                "disableKillSwitch" -> handleDisableKillSwitch(result)
                "activateKillSwitch" -> handleActivateKillSwitch(result)
                "deactivateKillSwitch" -> handleDeactivateKillSwitch(result)
                "isKillSwitchActive" -> result.success(isActive)
                "getKillSwitchCapabilities" -> handleGetCapabilities(result)
                "testKillSwitch" -> {
                    val duration = call.argument<Int>("durationSeconds") ?: 5
                    handleTestKillSwitch(duration, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleEnableKillSwitch(result: MethodChannel.Result) {
        scope.launch {
            try {
                // Check if root access available
                val hasRoot = checkRootAccess()
                if (hasRoot) {
                    Log.i(TAG, "Root access available - iptables mode enabled")
                    result.success(true)
                } else {
                    Log.w(TAG, "No root access - recommend system settings")
                    // Fallback: User must enable "Block connections without VPN" in settings
                    result.success(false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error enabling kill switch: ${e.message}")
                result.error("ENABLE_FAILED", e.message, null)
            }
        }
    }

    private fun handleDisableKillSwitch(result: MethodChannel.Result) {
        scope.launch {
            try {
                if (isActive) {
                    deactivateIptables()
                    isActive = false
                }
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error disabling kill switch: ${e.message}")
                result.error("DISABLE_FAILED", e.message, null)
            }
        }
    }

    private fun handleActivateKillSwitch(result: MethodChannel.Result) {
        scope.launch {
            try {
                activateIptables()
                isActive = true
                Log.i(TAG, "Kill switch activated - traffic blocked")
                result.success(null)
            } catch (e: Exception) {
                Log.e(TAG, "Error activating kill switch: ${e.message}")
                result.error("ACTIVATE_FAILED", e.message, null)
            }
        }
    }

    private fun handleDeactivateKillSwitch(result: MethodChannel.Result) {
        scope.launch {
            try {
                if (isActive) {
                    deactivateIptables()
                    isActive = false
                }
                Log.i(TAG, "Kill switch deactivated")
                result.success(null)
            } catch (e: Exception) {
                Log.e(TAG, "Error deactivating kill switch: ${e.message}")
                result.error("DEACTIVATE_FAILED", e.message, null)
            }
        }
    }

    private fun handleGetCapabilities(result: MethodChannel.Result) {
        scope.launch {
            try {
                val capabilities = mapOf(
                    "supported" to true,
                    "method" to if (checkRootAccess()) "iptables" else "system_settings",
                    "android_version" to android.os.Build.VERSION.SDK_INT,
                    "requires_root" to !checkRootAccess()
                )
                result.success(capabilities)
            } catch (e: Exception) {
                result.error("GET_CAPABILITIES_FAILED", e.message, null)
            }
        }
    }

    private fun handleTestKillSwitch(durationSeconds: Int, result: MethodChannel.Result) {
        scope.launch {
            try {
                Log.i(TAG, "Testing kill switch for ${durationSeconds}s...")
                activateIptables()
                delay(durationSeconds * 1000L)
                deactivateIptables()
                Log.i(TAG, "Kill switch test completed")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Kill switch test failed: ${e.message}")
                result.error("TEST_FAILED", e.message, null)
            }
        }
    }

    /**
     * Activate iptables rules to block non-VPN traffic
     *
     * Rules:
     * 1. Drop all traffic by default (IN, OUT, FORWARD)
     * 2. Allow loopback (localhost communication)
     * 3. Allow VPN traffic (tun0, tun1, etc.)
     * 4. Allow DNS queries (port 53)
     */
    private suspend fun activateIptables() = withContext(Dispatchers.IO) {
        try {
            // Default policies - DROP all traffic
            executeCommand("iptables -P INPUT DROP")
            executeCommand("iptables -P OUTPUT DROP")
            executeCommand("iptables -P FORWARD DROP")

            // Allow loopback (necessary for system stability)
            executeCommand("iptables -A INPUT -i lo -j ACCEPT")
            executeCommand("iptables -A OUTPUT -o lo -j ACCEPT")

            // Allow VPN interface (tun0 is standard, but check others too)
            for (i in 0..5) {
                val tunInterface = "tun$i"
                executeCommand("iptables -A INPUT -i $tunInterface -j ACCEPT")
                executeCommand("iptables -A OUTPUT -o $tunInterface -j ACCEPT")
            }

            // Allow DNS queries (needed for domain resolution)
            executeCommand("iptables -A OUTPUT -p udp -m udp --dport 53 -j ACCEPT")
            executeCommand("iptables -A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT")

            Log.i(TAG, "iptables rules activated - traffic blocked except VPN")
        } catch (e: Exception) {
            Log.e(TAG, "Error activating iptables: ${e.message}")
            throw e
        }
    }

    /**
     * Deactivate iptables rules - restore normal traffic
     */
    private suspend fun deactivateIptables() = withContext(Dispatchers.IO) {
        try {
            // Reset to ACCEPT (allow all)
            executeCommand("iptables -P INPUT ACCEPT")
            executeCommand("iptables -P OUTPUT ACCEPT")
            executeCommand("iptables -P FORWARD ACCEPT")

            // Flush all rules
            executeCommand("iptables -F")
            executeCommand("iptables -X")

            Log.i(TAG, "iptables rules deactivated - traffic allowed")
        } catch (e: Exception) {
            Log.e(TAG, "Error deactivating iptables: ${e.message}")
            throw e
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
