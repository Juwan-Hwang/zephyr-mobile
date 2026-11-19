package com.zephyr.app.di

import com.zephyr.engine.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TrustedWifiTest {
    @Test fun firstInstallHasNoPrototypeData() {
        val s = Settings()
        assertEquals(emptyList<String>(), s.trustedWifi)
        assertTrue(s.disconnectOnTrusted) // contract §16.c default; an empty list has no effect
        assertFalse(s.shareAnonymousPattern)
    }

    @Test fun addTrimsAndSkipsDuplicates() {
        val s = TrustedWifi.add(Settings(), "  Office 5G ")!!
        assertEquals(listOf("Office 5G"), s.trustedWifi)
        assertNull(TrustedWifi.add(s, "Office 5G"))
        assertNull(TrustedWifi.add(s, "   "))
        assertEquals(listOf("Office 5G", "家"), TrustedWifi.add(s, "家")!!.trustedWifi)
    }

    @Test fun removeKeepsOrder() {
        val s = Settings(trustedWifi = listOf("a", "b", "c"))
        assertEquals(listOf("a", "c"), TrustedWifi.remove(s, "b").trustedWifi)
        assertEquals(listOf("a", "b", "c"), TrustedWifi.remove(s, "x").trustedWifi)
    }
}

/** Contract §16.c: SSID 1–32 bytes of UTF‑8, at most 50 networks. */
class TrustedWifiLimitsTest {
    @Test fun ssidByteLimitAndListCap() {
        org.junit.Assert.assertNull(TrustedWifi.add(Settings(), "x".repeat(33)))
        org.junit.Assert.assertNotNull(TrustedWifi.add(Settings(), "x".repeat(32)))
        org.junit.Assert.assertNull(TrustedWifi.add(Settings(), "咖啡".repeat(6))) // 36 bytes
        val full = Settings(trustedWifi = List(50) { "n$it" })
        org.junit.Assert.assertNull(TrustedWifi.add(full, "one more"))
    }
}
