package com.blackoutkit.vpn

import androidx.annotation.Keep

/** Candidate JNI ABI. No library is loaded automatically or exposed to the service. */
@Keep
internal object OpenVpnNativeBridge {
    fun loadCandidate() {
        System.loadLibrary("openvpn-candidate")
    }

    external fun nativeCreate(): Long

    external fun nativeRunV3(
        handle: Long,
        callbacks: OpenVpnTunCallbacks,
        profile: ByteArray,
        authentication: Array<ByteArray>,
    ): Int

    external fun nativeReconnect(handle: Long): Boolean

    external fun nativeCancel(handle: Long)

    external fun nativeRelease(handle: Long): Boolean
}
