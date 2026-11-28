package com.blackoutkit.vpn

import android.net.VpnService

/** Keeps native handles and secret bytes inside the candidate service lifetime. */
internal class OpenVpnAndroidBackend(
    private val handle: Long,
    private val payload: OpenVpnStartPayload,
    service: VpnService,
    current: () -> Boolean,
    policy: OpenVpnAppPolicy,
) : OpenVpnSession.Backend {
    private var report: (Boolean) -> Unit = {}
    val callbacks = OpenVpnTunCallbacks(service, current, policy) { report(it) }

    override fun run(report: (Boolean) -> Unit) {
        this.report = report
        val credentials = payload.credentials
        try {
            OpenVpnNativeBridge.nativeRunV3(
                handle,
                callbacks,
                payload.profile,
                arrayOf(
                    credentials?.username ?: ByteArray(0),
                    credentials?.password ?: ByteArray(0),
                    credentials?.keyPassword ?: ByteArray(0),
                ),
            )
        } finally {
            payload.clear()
            this.report = {}
        }
    }

    override fun reconnect(): Boolean = OpenVpnNativeBridge.nativeReconnect(handle)

    override fun cancel() = OpenVpnNativeBridge.nativeCancel(handle)

    override fun release() {
        payload.clear()
        check(OpenVpnNativeBridge.nativeRelease(handle)) { "OpenVPN native ownership not released" }
    }
}
