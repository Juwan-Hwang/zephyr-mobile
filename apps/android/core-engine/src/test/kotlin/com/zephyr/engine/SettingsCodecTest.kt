package com.zephyr.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Contract §16.c: defaults table and per-field lenient decoding (E42). */
class SettingsCodecTest {
    @Test fun defaultsMatchContractTable() {
        val s = Settings()
        assertTrue(s.onDemand)
        assertEquals(emptyList<String>(), s.trustedWifi)
        assertTrue(s.disconnectOnTrusted)
        assertFalse(s.localProxyEnabled)
        assertEquals(7890, s.localProxyPort)
        assertTrue(s.localProxyAuth)
        assertTrue(s.testOnWifiOnly)
        assertEquals(24, s.latencyTtlHours)
        assertEquals(12, s.autoUpdateHours)
        assertTrue(s.updateOnWifiOnly)
        assertFalse(s.showChangesBeforeUpdate)
        assertEquals(TunStack.GVISOR, s.tun.stack)
        assertEquals(9000, s.tun.mtu)
        assertFalse(s.tun.ipv6)
        assertTrue(s.tun.strictRoute)
        assertEquals(Accent.BLUE, s.accent)
        assertEquals(Appearance.SYSTEM, s.appearance)
        assertFalse(s.shareDiagnostics)
        assertFalse(s.shareAnonymousPattern)
        assertEquals(emptyList<String>(), s.tun.excludedApps)
    }

    /** A blob as v0.3 builds stored it: no shareDiagnostics, old field set, user's own values. */
    private val v03 = """
        {"onDemand":false,"trustedWifi":["Office 5G"],"disconnectOnTrusted":false,"localProxyPort":8080,"localProxyAuth":false,
         "testOnWifiOnly":false,"latencyTtlHours":72,"autoUpdateHours":6,"updateOnWifiOnly":false,"showChangesBeforeUpdate":true,
         "dns":{"fakeIp":false,"nameservers":["https://1.1.1.1/dns-query"]},"tun":{"stack":"system","mtu":1500,"ipv6":true},
         "accent":"pink","appearance":"dark","shareAnonymousPattern":true}
    """.trimIndent()

    @Test fun v03SettingsDecodeAndKeepFields() {
        val s = SettingsCodec.decode(v03)
        assertFalse(s.onDemand)
        assertEquals(listOf("Office 5G"), s.trustedWifi)
        assertFalse(s.disconnectOnTrusted)
        assertEquals(8080, s.localProxyPort)
        assertFalse(s.localProxyAuth)
        assertFalse(s.testOnWifiOnly)
        assertEquals(72, s.latencyTtlHours)
        assertEquals(6, s.autoUpdateHours)
        assertFalse(s.updateOnWifiOnly)
        assertTrue(s.showChangesBeforeUpdate)
        assertFalse(s.dns.fakeIp)
        assertEquals(listOf("https://1.1.1.1/dns-query"), s.dns.nameservers)
        assertEquals(DnsSettings().fallback, s.dns.fallback) // missing nested field → its default only
        assertEquals(TunStack.SYSTEM, s.tun.stack)
        assertEquals(1500, s.tun.mtu)
        assertTrue(s.tun.ipv6)
        assertEquals(Accent.PINK, s.accent)
        assertEquals(Appearance.DARK, s.appearance)
        assertFalse(s.shareDiagnostics) // new field → default
    }

    @Test fun oneBadFieldFallsBackAlone() {
        val raw = """{"onDemand":"yes","accent":"purple","localProxyPort":80,"latencyTtlHours":1,"autoUpdateHours":null,
            "tun":{"mtu":576,"ipv6":true,"stack":42},"appearance":"light","unknownField":{"a":1},"trustedWifi":["Home","Home",""]}"""
        val s = SettingsCodec.decode(raw)
        val d = Settings()
        assertEquals(d.onDemand, s.onDemand)
        assertEquals(d.accent, s.accent)
        assertEquals(d.localProxyPort, s.localProxyPort)
        assertEquals(d.latencyTtlHours, s.latencyTtlHours)
        assertEquals(d.autoUpdateHours, s.autoUpdateHours)
        assertEquals(d.tun.mtu, s.tun.mtu)
        assertEquals(d.tun.stack, s.tun.stack)
        assertTrue(s.tun.ipv6)
        assertEquals(Appearance.LIGHT, s.appearance)
        assertEquals(listOf("Home"), s.trustedWifi)
    }

    @Test fun garbageIsDefaults() {
        assertEquals(Settings(), SettingsCodec.decode("not json"))
        assertEquals(Settings(), SettingsCodec.decode("[]"))
    }

    @Test fun roundTrip() {
        val s = Settings(onDemand = false, latencyTtlHours = 12, autoUpdateHours = 48, accent = Accent.GREEN)
        assertEquals(s, SettingsCodec.decode(SettingsCodec.encode(s)))
    }

    @Test fun rangesAndOptions() {
        val d = Settings()
        assertTrue(SettingsCodec.isValid(d))
        assertFalse(SettingsCodec.isValid(d.copy(localProxyPort = 1023)))
        assertTrue(SettingsCodec.isValid(d.copy(localProxyPort = 1024)))
        assertTrue(SettingsCodec.isValid(d.copy(localProxyPort = 65535)))
        assertFalse(SettingsCodec.isValid(d.copy(tun = d.tun.copy(mtu = 1279))))
        assertTrue(SettingsCodec.isValid(d.copy(tun = d.tun.copy(mtu = 1280))))
        assertFalse(SettingsCodec.isValid(d.copy(tun = d.tun.copy(mtu = 9001))))
        listOf(6, 12, 24, 72).forEach { assertTrue(SettingsCodec.isValid(d.copy(latencyTtlHours = it))) }
        assertFalse(SettingsCodec.isValid(d.copy(latencyTtlHours = 48)))
        listOf(6, 12, 24, 48).forEach { assertTrue(SettingsCodec.isValid(d.copy(autoUpdateHours = it))) }
        assertFalse(SettingsCodec.isValid(d.copy(autoUpdateHours = 72)))
        assertFalse(SettingsCodec.isValid(d.copy(trustedWifi = listOf("x".repeat(33)))))
        assertTrue(SettingsCodec.isValid(d.copy(trustedWifi = listOf("家".repeat(10))))) // 30 bytes
        assertFalse(SettingsCodec.isValid(d.copy(trustedWifi = listOf("家".repeat(11))))) // 33 bytes
        assertFalse(SettingsCodec.isValid(d.copy(trustedWifi = List(51) { "n$it" })))
    }
}
