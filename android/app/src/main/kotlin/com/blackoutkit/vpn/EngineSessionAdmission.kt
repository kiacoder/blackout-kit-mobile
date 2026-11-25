package com.blackoutkit.vpn

/** Exclusive owner of shared native engines, including startup and failed cleanup. */
internal class EngineSessionAdmission {
    private var owner: Any? = null

    @Synchronized
    fun claim(token: Any): Boolean {
        if (owner != null && owner !== token) return false
        owner = token
        return true
    }

    @Synchronized
    fun owns(token: Any): Boolean = owner === token

    @Synchronized
    fun release(token: Any) {
        if (owner === token) owner = null
    }

    companion object {
        val process = EngineSessionAdmission()
    }
}
