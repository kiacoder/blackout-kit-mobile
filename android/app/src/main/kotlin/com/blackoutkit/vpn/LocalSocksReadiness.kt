package com.blackoutkit.vpn

import java.net.InetSocketAddress
import java.net.Socket

internal object LocalSocksReadiness {
    fun await(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                socket.soTimeout = timeoutMs
                val output = socket.getOutputStream()
                val input = socket.getInputStream()
                output.write(byteArrayOf(0x05, 0x01, 0x00))
                output.flush()
                val version = input.read()
                val method = input.read()
                version == 0x05 && method == 0x00
            }
        } catch (_: Exception) {
            false
        }
    }
}
