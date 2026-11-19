package com.zephyr.app.vpn

import com.zephyr.app.ui.library.TrustedWifiNotice
import com.zephyr.app.ui.library.trustedWifiNotice
import com.zephyr.engine.NetworkKind
import com.zephyr.engine.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Contract §16.a③ / ⑤ (E04, E01): on-demand and trusted Wi‑Fi decisions, pure so they run on the JVM. */
class OnDemandPolicyTest {
    private val home = Settings(onDemand = true, trustedWifi = listOf("Home"), disconnectOnTrusted = true)

    @Test fun autoConnectNeedsOnDemandAManualConnectAndExistingConsent() {
        assertTrue(OnDemand.mayAutoConnect(onDemand = true, armed = true, hasConsent = true))
        assertFalse(OnDemand.mayAutoConnect(onDemand = false, armed = true, hasConsent = true))
        // never connected by hand, or the last manual action was a disconnect
        assertFalse(OnDemand.mayAutoConnect(onDemand = true, armed = false, hasConsent = true))
        // never prompt VPN consent on our own
        assertFalse(OnDemand.mayAutoConnect(onDemand = true, armed = true, hasConsent = false))
    }

    @Test fun unknownSsidIsNeverTrustedAndAlwaysOnNeverDisconnects() {
        assertTrue(OnDemand.onTrustedNetwork(home, "Home", alwaysOn = false))
        assertFalse(OnDemand.onTrustedNetwork(home, null, alwaysOn = false))
        assertFalse(OnDemand.onTrustedNetwork(home, "Cafe", alwaysOn = false))
        assertFalse(OnDemand.onTrustedNetwork(home, "Home", alwaysOn = true))
        assertFalse(OnDemand.onTrustedNetwork(home.copy(disconnectOnTrusted = false), "Home", alwaysOn = false))
        assertFalse(OnDemand.onTrustedNetwork(home.copy(trustedWifi = emptyList()), "Home", alwaysOn = false))
    }

    @Test fun pausedOnTrustedReconnectsWhenLeavingAndStopsWithoutOnDemand() {
        assertEquals(OnDemand.Paused.STAY, OnDemand.whilePaused(home, hasNetwork = true, ssid = "Home", alwaysOn = false))
        assertEquals(OnDemand.Paused.STAY, OnDemand.whilePaused(home, hasNetwork = false, ssid = null, alwaysOn = false))
        assertEquals(OnDemand.Paused.RESUME, OnDemand.whilePaused(home, hasNetwork = true, ssid = null, alwaysOn = false)) // cellular / unknown
        assertEquals(OnDemand.Paused.RESUME, OnDemand.whilePaused(home, hasNetwork = true, ssid = "Cafe", alwaysOn = false))
        assertEquals(OnDemand.Paused.RESUME, OnDemand.whilePaused(home.copy(trustedWifi = emptyList()), true, "Home", false))
        assertEquals(OnDemand.Paused.RESUME, OnDemand.whilePaused(home, true, "Home", alwaysOn = true))
        assertEquals(OnDemand.Paused.STOP, OnDemand.whilePaused(home.copy(onDemand = false), true, "Cafe", false))
    }

    @Test fun networkSwitchKeyIgnoresOfflineAndFollowsKindAndSsid() {
        assertNull(NetworkMonitor.changeKey(hasNetwork = false, kind = NetworkKind.OTHER, ssid = null, network = null))
        val wifiA = NetworkMonitor.changeKey(true, NetworkKind.WIFI, "A", "net1")
        assertEquals(wifiA, NetworkMonitor.changeKey(true, NetworkKind.WIFI, "A", "net2")) // same SSID, new handle
        assertNotEquals(wifiA, NetworkMonitor.changeKey(true, NetworkKind.WIFI, "B", "net1"))
        assertNotEquals(wifiA, NetworkMonitor.changeKey(true, NetworkKind.CELLULAR, null, "net3"))
        // SSID unknown: the network handle decides
        assertNotEquals(NetworkMonitor.changeKey(true, NetworkKind.WIFI, null, "n1"), NetworkMonitor.changeKey(true, NetworkKind.WIFI, null, "n2"))
    }

    @Test fun trustedWifiRowNotice() {
        assertEquals(TrustedWifiNotice.ALWAYS_ON, trustedWifiNotice(home, alwaysOn = true, hasPermission = false, locationOn = false))
        assertEquals(TrustedWifiNotice.NEEDS_PERMISSION, trustedWifiNotice(home, alwaysOn = false, hasPermission = false, locationOn = true))
        assertEquals(TrustedWifiNotice.LOCATION_OFF, trustedWifiNotice(home, alwaysOn = false, hasPermission = true, locationOn = false))
        assertEquals(TrustedWifiNotice.NONE, trustedWifiNotice(home, alwaysOn = false, hasPermission = true, locationOn = true))
        assertEquals(TrustedWifiNotice.NONE, trustedWifiNotice(home.copy(trustedWifi = emptyList()), false, false, false))
        assertEquals(TrustedWifiNotice.NONE, trustedWifiNotice(home.copy(disconnectOnTrusted = false), false, false, false))
    }
}
