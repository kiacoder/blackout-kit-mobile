package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class SiteProbeRunnerTest {
    @Test
    fun nativeRequestWithoutNetworkFailsEveryHostWithoutFallback() {
        val hosts = listOf("example.invalid", "second.invalid")
        val request = SiteProbeRequest(hosts, 10809, 1000, true, 1L)
        val outcomes = SiteProbeRunner(null).run(request)
        assertEquals(hosts, outcomes.map { it["host"] })
        for (outcome in outcomes) {
            assertFalse(outcome["ok"] as Boolean)
            assertNull(outcome["statusCode"])
            assertNull(outcome["latencyMs"])
            assertEquals("VPN network not accessible for verification", outcome["error"])
        }
    }

    @Test
    fun nonNativeResultsAreNotReclassifiedAsNativeSessionChanges() {
        val runner = SiteProbeRunner(null)
        val request = SiteProbeRequest(listOf("example.invalid"), 10809, 1000, false, 1L)
        val outcomes = listOf(runner.failedSite("example.invalid", "test result"))
        assertEquals(outcomes, runner.currentOutcomes(request, outcomes))
    }
}
