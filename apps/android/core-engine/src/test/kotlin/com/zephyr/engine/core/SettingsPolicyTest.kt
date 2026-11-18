package com.zephyr.engine.core

import com.zephyr.engine.DnsSettings
import com.zephyr.engine.Settings
import com.zephyr.engine.TunStack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Release audit #208 E15 / E16: settings validation and which changes hot-reload the core. */
class SettingsPolicyTest {
    @Test fun validatesLikeIos() {
        val d = Settings()
        assertTrue(CoreEngine.isValid(d))
        assertFalse(CoreEngine.isValid(d.copy(tun = d.tun.copy(mtu = 575))))
        assertFalse(CoreEngine.isValid(d.copy(tun = d.tun.copy(mtu = 9001))))
        assertTrue(CoreEngine.isValid(d.copy(tun = d.tun.copy(mtu = 576))))
        assertFalse(CoreEngine.isValid(d.copy(localProxyPort = 0)))
        assertFalse(CoreEngine.isValid(d.copy(latencyTtlHours = 0)))
        assertFalse(CoreEngine.isValid(d.copy(autoUpdateHours = 0)))
    }

    @Test fun sanitizesStoredValuesIntoRange() {
        val d = Settings()
        val s = CoreEngine.sanitized(d.copy(localProxyPort = 70_000, latencyTtlHours = -1, tun = d.tun.copy(mtu = 65_535)))
        assertTrue(CoreEngine.isValid(s))
        assertEquals(9000, s.tun.mtu)
        assertEquals(d.localProxyPort, s.localProxyPort)
        assertEquals(d.latencyTtlHours, s.latencyTtlHours)
    }

    @Test fun runtimeFieldsTriggerReload() {
        val d = Settings()
        assertTrue(CoreEngine.affectsRuntime(d, d.copy(dns = DnsSettings(fakeIp = !d.dns.fakeIp))))
        assertTrue(CoreEngine.affectsRuntime(d, d.copy(tun = d.tun.copy(stack = TunStack.values().first { it != d.tun.stack }))))
        assertTrue(CoreEngine.affectsRuntime(d, d.copy(localProxyEnabled = !d.localProxyEnabled)))
        assertTrue(CoreEngine.affectsRuntime(d, d.copy(localProxyAuth = !d.localProxyAuth)))
        assertFalse(CoreEngine.affectsRuntime(d, d.copy(testOnWifiOnly = !d.testOnWifiOnly)))
        assertFalse(CoreEngine.affectsRuntime(d, d.copy(tun = d.tun.copy(mtu = 1500)))) // Builder-level: next connect
    }
}
