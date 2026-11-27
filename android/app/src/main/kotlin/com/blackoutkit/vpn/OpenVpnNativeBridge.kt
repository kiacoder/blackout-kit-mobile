package com.blackoutkit.vpn

import androidx.annotation.Keep

/** Candidate JNI ABI. No library is loaded automatically or exposed to the service. */
@Keep
internal object OpenVpnNativeBridge {
    fun loadCandidate() {
        System.loadLibrary("openvpn-candidate")
    }

    external fun nativeCreate(): Long

    external fun nativeRun(
        handle: Long,
        callbacks: OpenVpnTunCallbacks,
        profile: ByteArray,
        username: ByteArray,
        password: ByteArray,
    ): Int

    external fun nativeCancel(handle: Long)

    external fun nativeRelease(handle: Long): Boolean
}
