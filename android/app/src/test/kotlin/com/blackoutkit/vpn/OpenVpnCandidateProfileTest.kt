package com.blackoutkit.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenVpnCandidateProfileTest {
    private val profile =
        "client\ndev tun\nproto udp\nremote fixture.test 1194\nremote-cert-tls server\n" +
            "<ca>\nfixture\n</ca>\n<cert>\nfixture\n</cert>\n<key>\nfixture\n</key>\n"

    @Test
    fun admitsSelfContainedCertificateProfile() {
        assertTrue(OpenVpnCandidateProfile.admits(profile))
        assertTrue(OpenVpnCandidateProfile.admits(profile.replace("\n", "\r\n")))
    }

    @Test
    fun rejectsUnsafeOrUnsupportedDirectives() {
        for (extra in listOf(
            "up /tmp/fixture",
            "ca /tmp/fixture",
            "auth-user-pass",
            "plugin foo",
            "dev tap",
            "remote-cert-tls client",
            "remote fixture.test \\",
            "<connection>",
            "setenv foo bar",
            "<ca>\nother\n</ca>",
            "remote \"fixture.test\" 1194",
        )) {
            assertFalse(OpenVpnCandidateProfile.admits(profile + extra))
        }
    }

    @Test
    fun rejectsMissingVerificationAndMalformedBlocks() {
        assertFalse(OpenVpnCandidateProfile.admits(profile.replace("remote-cert-tls server\n", "")))
        assertFalse(OpenVpnCandidateProfile.admits(profile.replace("</key>", "")))
        assertFalse(OpenVpnCandidateProfile.admits(profile.replace("<key>\nfixture", "<key>")))
        assertFalse(OpenVpnCandidateProfile.admits(profile.replace("remote fixture.test 1194\n", "")))
    }
}
