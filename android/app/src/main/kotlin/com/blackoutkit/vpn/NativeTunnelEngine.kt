package com.blackoutkit.vpn

import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.wireguard.android.backend.GoBackend as WG
import org.amnezia.awg.GoBackend as AWG

/** Owns only the duplicate transferred to JNI. Caller retains the service TUN.
 * All operations are serialized, including library loading and shutdown.
 * No profile is persisted; native errors are deliberately not echoed to Dart.
 */
internal object NativeTunnelEngine {
    private val lifecycle = NativeTunnelLifecycle()
    private var combinedLibraryLoaded = false
    private val verified = mutableSetOf<String>()
    @Volatile var lastError: String? = null
        private set

    @Synchronized fun available(protocol: String): Boolean {
        if (!BuildConfig.ENABLE_EXPERIMENTAL_NATIVE_TUNNELS) return false
        if (protocol !in setOf("wireguard", "amneziawg")) return false
        if (!GoRuntimeAdmission.process.claim(GoRuntimeAdmission.Family.NATIVE_TUNNELS)) {
            lastError = GoRuntimeAdmission.RESTART_REQUIRED
            return false
        }
        if (protocol in verified) return true
        return try {
            if (!combinedLibraryLoaded) {
                System.loadLibrary("blackout-tunnels")
                combinedLibraryLoaded = true
            }
            // Probe the extended ABI before transferring any descriptor. Older
            // libraries cannot silently start without lifecycle monitoring.
            if (protocol == "amneziawg") {
                AWG.awgVersion()
                check(AWG.awgIsClosed(-1) == 1)
            } else {
                WG.wgVersion()
                check(WG.wgIsClosed(-1) == 1)
            }
            verified.add(protocol)
            true
        } catch (_: LinkageError) { false } catch (_: Exception) { false }
    }

    @Synchronized fun start(service: VpnService, protocol: String, tun: ParcelFileDescriptor, settings: String): Boolean {
        lastError = null
        if (!available(protocol)) {
            if (lastError == null) lastError = "Native tunnel is disabled or its reviewed library is missing"
            return false
        }
        val backend = object : NativeTunnelLifecycle.Backend {
            override fun turnOn(fd: Int, settings: String): Int =
                if (protocol == "amneziawg") AWG.awgTurnOn("blackout", fd, settings)
                else WG.wgTurnOn("blackout", fd, settings)
            override fun turnOff(handle: Int) {
                if (protocol == "amneziawg") AWG.awgTurnOff(handle) else WG.wgTurnOff(handle)
            }
            override fun isClosed(handle: Int): Boolean =
                if (protocol == "amneziawg") AWG.awgIsClosed(handle) != 0 else WG.wgIsClosed(handle) != 0
            override fun sockets(handle: Int): List<Int> =
                if (protocol == "amneziawg") listOf(AWG.awgGetSocketV4(handle), AWG.awgGetSocketV6(handle))
                else listOf(WG.wgGetSocketV4(handle), WG.wgGetSocketV6(handle))
        }
        val result = lifecycle.start(backend, settings,
            detach = { tun.dup().detachFd() },
            closeUndelivered = { ParcelFileDescriptor.adoptFd(it).close() },
            protect = { service.protect(it) })
        lastError = lifecycle.lastError
        return result
    }

    @Synchronized fun isClosed(): Boolean = lifecycle.isClosed()

    @Synchronized fun stop() = lifecycle.stop()
}
