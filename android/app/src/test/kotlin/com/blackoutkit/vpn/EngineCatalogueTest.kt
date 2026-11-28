package com.blackoutkit.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class EngineCatalogueTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun missingLibrariesDoNotAdvertiseNativeOrSingbox() {
        val report = EngineCatalogue(null, null, true, true).report()
        assertEquals(false, report["nativeWireguardAvailable"])
        assertEquals(false, report["xrayAvailable"])
        assertEquals(false, report["singboxAvailable"])
        assertEquals(false, report["mihomoAvailable"])
        assertEquals(emptyList<String>(), report["singboxProtocols"])
    }

    @Test
    fun embeddedRuntimeBlocksNativeFamilyWithoutHidingXray() {
        folder.newFile("libgojni.so")
        folder.newFile("libblackout-tunnels.so")
        val report = EngineCatalogue(folder.root, GoRuntimeAdmission.Family.EMBEDDED, true, false).report()
        assertEquals(true, report["xrayAvailable"])
        assertEquals(false, report["nativeAmneziawgAvailable"])
        assertEquals(true, report["runtimeRestartRequired"])
        assertEquals(listOf("amneziawg"), report["restartRequiredProtocols"])
    }

    @Test
    fun nativeOwnerKeepsSubprocessProtocolsWhenPackaged() {
        for (name in listOf(
            "libgojni.so",
            "libblackout-tunnels.so",
            "libsingbox.so",
            "libtun2socks.so",
            "libfdlauncher.so",
        )) {
            folder.newFile(name)
        }
        val report = EngineCatalogue(folder.root, GoRuntimeAdmission.Family.NATIVE_TUNNELS, true, false).report()
        assertEquals(true, report["nativeWireguardAvailable"])
        assertEquals(false, report["xrayAvailable"])
        assertEquals(true, report["singboxAvailable"])
        assertEquals(listOf("hysteria2", "tuic", "anytls"), report["singboxProtocols"])
        val restart = report["restartRequiredProtocols"] as List<*>
        assertTrue("vless" in restart)
        assertFalse("wireguard" in restart)
        assertFalse("hysteria2" in restart)
    }

    @Test
    fun nativeFeatureFlagDisablesCandidateEvenWhenPackaged() {
        folder.newFile("libblackout-tunnels.so")
        val report = EngineCatalogue(folder.root, null, false, false).report()
        assertEquals(false, report["nativeWireguardAvailable"])
        assertEquals(false, report["nativeAmneziawgAvailable"])
    }

    @Test
    fun openVpnRequiresBothFlagAndLibrary() {
        assertEquals(false, EngineCatalogue(folder.root, null, false, false, true).report()["openVpnAvailable"])
        folder.newFile("libopenvpn-candidate.so")
        assertEquals(false, EngineCatalogue(folder.root, null, false, false).report()["openVpnAvailable"])
        val candidate = EngineCatalogue(folder.root, null, false, false, true).report()
        assertEquals(true, candidate["openVpnAvailable"])
        assertFalse("openvpn" in (candidate["unavailableProtocols"] as List<*>))
    }
}
