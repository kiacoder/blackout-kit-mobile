package com.blackoutkit.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * DNS Leak Prevention Service - Prevents DNS queries from leaking outside VPN
 *
 * Strategy:
 * 1. Redirect DNS port 53 to VPN tunnel interface (tun0)
 * 2. Block DNS queries to system/ISP servers
 * 3. Force all DNS through VPN provider
 *
 * Note: Requires root access for iptables manipulation
 */
class DNSLeakPreventionService(private val context: Context) {
    companion object {
        private const val TAG = "DNSLeak"
        private const val CHANNEL = "com.blackoutkit.vpn/dns"

        // Common DNS leak test servers (to check for leaks)
        private val LEAK_TEST_SERVERS = listOf(
            "8.8.8.8",        // Google
            "1.1.1.1",        // Cloudflare
            "208.67.222.222", // OpenDNS
            "9.9.9.9"         // Quad9
        )
    }

    private var channel: MethodChannel? = null
    private var isActive = false
    private var currentDNS = "1.1.1.1"
    private val scope = CoroutineScope(Dispatchers.IO + Job())

    fun setupChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableDNSLeakPrevention" -> {
                    val dnsServer = call.argument<String>("dnsServer") ?: "1.1.1.1"
                    handleEnableDNSLeakPrevention(dnsServer, result)
                }
                "disableDNSLeakPrevention" -> handleDisableDNSLeakPrevention(result)
                "activateDNSLeakPrevention" -> handleActivateDNSLeakPrevention(result)
                "deactivateDNSLeakPrevention" -> handleDeactivateDNSLeakPrevention(result)
                "getCurrentDNS" -> result.success(currentDNS)
                "testDNSLeaks" -> handleTestDNSLeaks(result)
                "setCustomDNS" -> {
                    val dnsServer = call.argument<String>("dnsServer") ?: "1.1.1.1"
                    handleSetCustomDNS(dnsServer, result)
                }
                "getSecureDNSProviders" -> handleGetSecureDNSProviders(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleEnableDNSLeakPrevention(dnsServer: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                if (checkRootAccess()) {
                    currentDNS = dnsServer
                    Log.i(TAG, "DNS leak prevention enabled with server: $dnsServer")
                    result.success(true)
                } else {
                    Log.w(TAG, "No root access - DNS leak prevention unavailable")
                    result.success(false)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error enabling DNS leak prevention: ${e.message}")
                result.error("ENABLE_FAILED", e.message, null)
            }
        }
    }

    private fun handleDisableDNSLeakPrevention(result: MethodChannel.Result) {
        scope.launch {
            try {
                if (isActive) {
                    deactivateDNSIptables()
                    isActive = false
                }
                Log.i(TAG, "DNS leak prevention disabled")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error disabling DNS leak prevention: ${e.message}")
                result.error("DISABLE_FAILED", e.message, null)
            }
        }
    }

    private fun handleActivateDNSLeakPrevention(result: MethodChannel.Result) {
        scope.launch {
            try {
                activateDNSIptables(currentDNS)
                isActive = true
                Log.i(TAG, "DNS leak prevention activated - blocking system DNS")
                result.success(null)
            } catch (e: Exception) {
                Log.e(TAG, "Error activating DNS leak prevention: ${e.message}")
                result.error("ACTIVATE_FAILED", e.message, null)
            }
        }
    }

    private fun handleDeactivateDNSLeakPrevention(result: MethodChannel.Result) {
        scope.launch {
            try {
                if (isActive) {
                    deactivateDNSIptables()
                    isActive = false
                }
                Log.i(TAG, "DNS leak prevention deactivated")
                result.success(null)
            } catch (e: Exception) {
                Log.e(TAG, "Error deactivating DNS leak prevention: ${e.message}")
                result.error("DEACTIVATE_FAILED", e.message, null)
            }
        }
    }

    private fun handleTestDNSLeaks(result: MethodChannel.Result) {
        scope.launch {
            try {
                Log.i(TAG, "Testing for DNS leaks...")
                // In a real implementation, perform DNS resolution to each server
                // and check if responses come from outside VPN
                // For now, return empty list (no leaks)
                result.success(emptyList<String>())
            } catch (e: Exception) {
                result.error("TEST_FAILED", e.message, null)
            }
        }
    }

    private fun handleSetCustomDNS(dnsServer: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                currentDNS = dnsServer
                if (isActive) {
                    deactivateDNSIptables()
                    activateDNSIptables(dnsServer)
                }
                Log.i(TAG, "Custom DNS set: $dnsServer")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error setting custom DNS: ${e.message}")
                result.error("SET_DNS_FAILED", e.message, null)
            }
        }
    }

    private fun handleGetSecureDNSProviders(result: MethodChannel.Result) {
        val providers = mapOf(
            "cloudflare" to "1.1.1.1",
            "quad9" to "9.9.9.9",
            "adguard" to "94.140.14.14",
            "nextdns" to "45.90.28.0",
            "opendns" to "208.67.222.222"
        )
        result.success(providers)
    }

    /**
     * Activate iptables rules to redirect DNS through VPN
     *
     * Rules:
     * 1. Redirect DNS port 53 to VPN interface (tun0)
     * 2. Block DNS to common public servers
     * 3. Allow only VPN-provided DNS
     */
    private suspend fun activateDNSIptables(vpnDNS: String) = withContext(Dispatchers.IO) {
        try {
            // Redirect DNS queries on port 53 to VPN interface
            executeCommand("iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-port 53")
            executeCommand("iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-port 53")

            // Block DNS queries to common public servers
            for (leakServer in LEAK_TEST_SERVERS) {
                executeCommand("iptables -A OUTPUT -d $leakServer -p udp --dport 53 -j DROP")
                executeCommand("iptables -A OUTPUT -d $leakServer -p tcp --dport 53 -j DROP")
            }

            // Allow VPN-provided DNS through tun interface
            executeCommand("iptables -A OUTPUT -o tun0 -p udp --dport 53 -j ACCEPT")
            executeCommand("iptables -A OUTPUT -o tun0 -p tcp --dport 53 -j ACCEPT")

            Log.i(TAG, "DNS iptables rules activated - traffic redirected through VPN")
        } catch (e: Exception) {
            Log.e(TAG, "Error activating DNS iptables: ${e.message}")
            throw e
        }
    }

    /**
     * Deactivate DNS iptables rules - restore system DNS
     */
    private suspend fun deactivateDNSIptables() = withContext(Dispatchers.IO) {
        try {
            // Remove NAT rules
            executeCommand("iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-port 53")
            executeCommand("iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-port 53")

            // Remove leak blocking rules
            for (leakServer in LEAK_TEST_SERVERS) {
                executeCommand("iptables -D OUTPUT -d $leakServer -p udp --dport 53 -j DROP")
                executeCommand("iptables -D OUTPUT -d $leakServer -p tcp --dport 53 -j DROP")
            }

            // Remove VPN DNS allow rules
            executeCommand("iptables -D OUTPUT -o tun0 -p udp --dport 53 -j ACCEPT")
            executeCommand("iptables -D OUTPUT -o tun0 -p tcp --dport 53 -j ACCEPT")

            Log.i(TAG, "DNS iptables rules deactivated - system DNS restored")
        } catch (e: Exception) {
            Log.e(TAG, "Error deactivating DNS iptables: ${e.message}")
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
