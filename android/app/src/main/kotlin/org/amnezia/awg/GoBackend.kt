// JNI declarations for the pinned official bridge; no upstream VPN service.
package org.amnezia.awg

internal object GoBackend {
    @JvmStatic external fun awgTurnOn(name: String, fd: Int, settings: String): Int
    @JvmStatic external fun awgTurnOff(handle: Int)
    @JvmStatic external fun awgGetSocketV4(handle: Int): Int
    @JvmStatic external fun awgGetSocketV6(handle: Int): Int
    @JvmStatic external fun awgIsClosed(handle: Int): Int
    @JvmStatic external fun awgVersion(): String
}
