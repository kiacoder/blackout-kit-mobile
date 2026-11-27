package com.blackoutkit.vpn

import android.net.VpnService

/** Keeps native handles and secret bytes inside the candidate service lifetime. */
internal class OpenVpnAndroidBackend(
    private val handle: Long,
    private val profile: String,
    service: VpnService,
    current: () -> Boolean,
    private val credentials: OpenVpnCredentials?,
) : OpenVpnSession.Backend {
    private var report: (Boolean) -> Unit = {}
    val callbacks = OpenVpnTunCallbacks(service, current) { report(it) }

    override fun run(report: (Boolean) -> Unit) {
        this.report = report
        val bytes = profile.toByteArray(Charsets.UTF_8)
        try {
            OpenVpnNativeBridge.nativeRunV3(
                handle,
                callbacks,
                bytes,
                arrayOf(
                    credentials?.username ?: ByteArray(0),
                    credentials?.password ?: ByteArray(0),
                    credentials?.keyPassword ?: ByteArray(0),
                ),
            )
        } finally {
            bytes.fill(0)
            credentials?.clear()
            this.report = {}
        }
    }

    override fun cancel() = OpenVpnNativeBridge.nativeCancel(handle)

    override fun release() {
        credentials?.clear()
        check(OpenVpnNativeBridge.nativeRelease(handle)) { "OpenVPN native ownership not released" }
    }
}
