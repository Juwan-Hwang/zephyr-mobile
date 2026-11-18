package com.zephyr.app.di

import com.zephyr.engine.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class TrustedWifiTest {
    @Test fun firstInstallHasNoPrototypeData() {
        val s = Settings()
        assertEquals(emptyList<String>(), s.trustedWifi)
        assertFalse(s.disconnectOnTrusted)
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
