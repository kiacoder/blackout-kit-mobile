// JNI declarations for the pinned official bridge; no upstream VPN service.
package com.wireguard.android.backend

internal object GoBackend {
    @JvmStatic external fun wgTurnOn(
        name: String,
        fd: Int,
        settings: String,
    ): Int

    @JvmStatic external fun wgTurnOff(handle: Int)

    @JvmStatic external fun wgGetSocketV4(handle: Int): Int

    @JvmStatic external fun wgGetSocketV6(handle: Int): Int

    @JvmStatic external fun wgIsClosed(handle: Int): Int

    @JvmStatic external fun wgVersion(): String
}
