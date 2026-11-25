package com.blackoutkit.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import android.util.Log
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import javax.net.ssl.HttpsURLConnection

internal class SiteProbeRequest(
    val urls: List<String>,
    val socksPort: Int,
    val timeoutMs: Int,
    val native: Boolean,
    val session: Long,
)

internal class SiteProbeRunner(
    private val context: Context?,
) {
    companion object {
        private const val TAG = "SiteProbeRunner"
        private const val HTTP_STATUS_MIN = 100
        private const val HTTP_STATUS_MAX = 599
        private const val MAX_PARALLEL_SITE_CHECKS = 8
        private const val SITE_FUTURE_GRACE_MS = 2_000L
        private const val VPN_NETWORK_WAIT_MS = 3_000L
        private const val VPN_NETWORK_POLL_MS = 100L
        private const val MAX_DNS_HOST_LENGTH = 253
        private const val MAX_DNS_LABEL_LENGTH = 63
    }

    fun run(request: SiteProbeRequest): List<Map<String, Any?>> {
        val network = if (request.native) awaitNativeProbeNetwork(request.session) else null
        if (request.native && network == null) {
            return request.urls.map { failedSite(it, "VPN network not accessible for verification") }
        }
        val pool = Executors.newFixedThreadPool(minOf(request.urls.size, MAX_PARALLEL_SITE_CHECKS))
        return try {
            val futures =
                request.urls.map { host ->
                    pool.submit(Callable { probe(request, host, network) })
                }
            futures.map { awaitResult(it, request.timeoutMs) }
        } finally {
            pool.shutdownNow()
        }
    }

    fun currentOutcomes(
        request: SiteProbeRequest,
        outcomes: List<Map<String, Any?>>,
    ): List<Map<String, Any?>> =
        if (request.native && !nativeSessionCurrent(request.session)) {
            request.urls.map { failedSite(it, "VPN session changed during verification") }
        } else {
            outcomes
        }

    private fun probe(
        request: SiteProbeRequest,
        host: String,
        network: Network?,
    ): Map<String, Any?> {
        if (network == null) {
            check(!request.native)
            return probeSiteThroughSocks(host, request.socksPort, request.timeoutMs)
        }
        val session = request.session
        val outcome =
            probeSite(host, request.timeoutMs) { target ->
                check(nativeSessionCurrent(session))
                network.openConnection(target, Proxy.NO_PROXY) as HttpsURLConnection
            }
        return if (nativeSessionCurrent(
                session,
            )
        ) {
            outcome
        } else {
            failedSite(host, "VPN session changed during verification")
        }
    }

    private fun awaitResult(
        future: Future<Map<String, Any?>>,
        timeoutMs: Int,
    ): Map<String, Any?> =
        try {
            future.get(timeoutMs + SITE_FUTURE_GRACE_MS, TimeUnit.MILLISECONDS)
        } catch (e: TimeoutException) {
            future.cancel(true)
            failedSite("", e.message ?: e.javaClass.simpleName)
        } catch (e: ExecutionException) {
            failedSite("", e.message ?: e.javaClass.simpleName)
        } catch (_: InterruptedException) {
            future.cancel(true)
            Thread.currentThread().interrupt()
            failedSite("", "Site verification interrupted")
        }

    private fun nativeSessionCurrent(session: Long): Boolean =
        BlackoutVpnService.isRunning &&
            BlackoutVpnService.activeNativeTunnel &&
            BlackoutVpnService.connectedAtMs == session

    /** Android may publish the VPN Network just after establish() returns. */
    private fun awaitNativeProbeNetwork(session: Long): Network? {
        val cm = context?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
        val deadline = SystemClock.elapsedRealtime() + VPN_NETWORK_WAIT_MS
        return try {
            var found: Network? = null
            while (nativeSessionCurrent(session) && found == null) {
                val network = cm.activeNetwork
                val caps = network?.let { cm.getNetworkCapabilities(it) }
                if (network != null && caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) {
                    found = network
                } else if (SystemClock.elapsedRealtime() >= deadline) {
                    break
                } else {
                    Thread.sleep(VPN_NETWORK_POLL_MS)
                }
            }
            found
        } catch (_: SecurityException) {
            null
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            null
        }
    }

    private fun drainResponse(conn: HttpsURLConnection) {
        try {
            conn.inputStream.use { it.read() }
        } catch (_: IOException) {
            try {
                conn.errorStream?.use { it.read() }
            } catch (_: IOException) {
                Log.d(TAG, "HTTP response body unavailable after status")
            }
        }
    }

    fun failedSite(
        host: String,
        reason: String,
    ): Map<String, Any?> =
        mapOf(
            "host" to host,
            "ok" to false,
            "statusCode" to null,
            "latencyMs" to null,
            "error" to reason,
        )

    /**
     * Fetches one URL through the loopback SOCKS inbound.
     *
     * Any HTTP response counts as a pass — the point of the check is whether
     * traffic *flows through the config*, and even a 403 or a captive-portal
     * 302 proves the round trip completed through the remote exit. Only
     * connect failures and timeouts count as failures, because those are the
     * cases where the config demonstrably cannot carry traffic.
     */
    private fun probeSiteThroughSocks(
        host: String,
        socksPort: Int,
        timeoutMs: Int,
    ): Map<String, Any?> =
        probeSite(host, timeoutMs) { target ->
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort))
            target.openConnection(proxy) as javax.net.ssl.HttpsURLConnection
        }

    private fun probeSite(
        host: String,
        timeoutMs: Int,
        open: (URL) -> javax.net.ssl.HttpsURLConnection,
    ): Map<String, Any?> {
        var conn: javax.net.ssl.HttpsURLConnection? = null
        val startedAt = SystemClock.elapsedRealtime()
        return try {
            // User-selected public destinations have no stable application-
            // controlled pin set. Keep Android's system CA and hostname
            // validation; never install a custom trust-all manager or verifier.
            require(
                host.length <= MAX_DNS_HOST_LENGTH &&
                    host.contains('.') &&
                    host.split('.').all { label ->
                        label.length in 1..MAX_DNS_LABEL_LENGTH &&
                            label.matches(Regex("[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"))
                    },
            )
            conn =
                open(URL("https://$host")).apply {
                    connectTimeout = timeoutMs
                    readTimeout = timeoutMs
                    requestMethod = "GET"
                    doInput = true
                    instanceFollowRedirects = false
                    useCaches = false
                    setRequestProperty("Connection", "close")
                }
            val code = conn.responseCode
            if (code !in HTTP_STATUS_MIN..HTTP_STATUS_MAX) return failedSite(host, "No valid HTTP response")
            // Drain a little so the connection is fully established and the
            // timing reflects a real round trip, then release it.
            drainResponse(conn)
            mapOf(
                "host" to host,
                "ok" to true,
                "statusCode" to code,
                "latencyMs" to (SystemClock.elapsedRealtime() - startedAt),
                "error" to null,
            )
        } catch (e: java.io.IOException) {
            failedSite(host, e.message ?: e.javaClass.simpleName)
        } catch (e: IllegalArgumentException) {
            failedSite(host, e.message ?: e.javaClass.simpleName)
        } catch (e: IllegalStateException) {
            failedSite(host, e.message ?: e.javaClass.simpleName)
        } catch (e: SecurityException) {
            failedSite(host, e.message ?: e.javaClass.simpleName)
        } finally {
            conn?.disconnect()
        }
    }
}
