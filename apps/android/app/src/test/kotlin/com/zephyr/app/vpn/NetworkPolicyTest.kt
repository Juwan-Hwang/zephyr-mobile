package com.zephyr.app.vpn

import androidx.work.NetworkType
import com.zephyr.app.widget.MidnightWidgetWorker
import com.zephyr.engine.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** Release audit #208: E30 / E23 / E01·U1 / E44 decisions, kept pure so they run on the JVM. */
class NetworkPolicyTest {
    @Test fun ssidIsUnquotedAndPlaceholdersAreUnknown() {
        assertEquals("Home 5G", NetworkMonitor.cleanSsid("\"Home 5G\""))
        assertEquals("cafe", NetworkMonitor.cleanSsid("cafe"))
        assertNull(NetworkMonitor.cleanSsid("<unknown ssid>"))
        assertNull(NetworkMonitor.cleanSsid("\"\""))
        assertNull(NetworkMonitor.cleanSsid(null))
    }

    @Test fun trustedDisconnectOnlyOnTransitionIntoTrustedNetwork() {
        val s = Settings(trustedWifi = listOf(" Home ", ""), disconnectOnTrusted = true)
        assertTrue(NetworkMonitor.shouldDisconnect(s, previousSsid = null, ssid = "Home"))     // cellular → Home
        assertTrue(NetworkMonitor.shouldDisconnect(s, previousSsid = "Cafe", ssid = "Home"))
        assertFalse(NetworkMonitor.shouldDisconnect(s, previousSsid = "Home", ssid = "Home"))  // connected by hand at Home
        assertFalse(NetworkMonitor.shouldDisconnect(s, previousSsid = "Home", ssid = null))    // SSID unknown: stay up
        assertFalse(NetworkMonitor.shouldDisconnect(s, previousSsid = null, ssid = "home"))    // exact match, like iOS
        assertFalse(NetworkMonitor.shouldDisconnect(s.copy(disconnectOnTrusted = false), null, "Home"))
        assertFalse(NetworkMonitor.shouldDisconnect(s.copy(trustedWifi = emptyList()), null, "Home"))
    }

    @Test fun wifiOnlyTestingGatesAutomaticTestsOnMeteredNetworks() {
        assertFalse(NetworkMonitor.autoTestAllowed(wifiOnly = true, metered = true))
        assertTrue(NetworkMonitor.autoTestAllowed(wifiOnly = true, metered = false))
        assertTrue(NetworkMonitor.autoTestAllowed(wifiOnly = false, metered = true))
    }

    @Test fun wifiOnlyUpdatesNeedAnUnmeteredNetwork() {
        assertEquals(NetworkType.UNMETERED, SubscriptionWorker.networkType(wifiOnly = true))
        assertEquals(NetworkType.CONNECTED, SubscriptionWorker.networkType(wifiOnly = false))
    }

    @Test fun midnightRefreshLandsJustAfterLocalMidnight() {
        val z = ZoneId.of("Asia/Shanghai")
        val d = MidnightWidgetWorker.delayToNextMidnight(ZonedDateTime.of(2026, 11, 18, 23, 59, 0, 0, z))
        assertEquals(65_000L, d) // 60 s to midnight + 5 s grace
        val e = MidnightWidgetWorker.delayToNextMidnight(ZonedDateTime.of(2026, 11, 18, 0, 0, 0, 0, z))
        assertEquals(86_405_000L, e)
    }
}
