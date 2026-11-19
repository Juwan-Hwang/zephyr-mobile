package com.zephyr.app.ui.subs

import com.zephyr.engine.Subscription
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

/** Contract §16.e ④ (U13). */
class SubscriptionWarningTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private fun at(y: Int, m: Int, d: Int, h: Int = 12) = LocalDateTime.of(y, m, d, h, 0).atZone(zone).toInstant().toEpochMilli()
    private val now = at(2026, 11, 6, 23)
    private fun sub(exp: Long?, used: Long? = null, total: Long? = null) = Subscription("s", "S", nodeCount = 1, usedBytes = used, totalBytes = total, expiresAt = exp)

    @Test fun prototypeSamples() {
        // Orbit: 3 days, 88% → amber; Nebula: 26 days, 57% → not.
        assertTrue(SubscriptionWarning.isWarning(sub(at(2026, 11, 9), 88, 100), now, zone))
        assertFalse(SubscriptionWarning.isWarning(sub(at(2026, 12, 2), 57, 100), now, zone))
    }

    @Test fun sevenCalendarDays() {
        assertTrue(SubscriptionWarning.isWarning(sub(at(2026, 11, 13, 1)), now, zone)) // 7 calendar days, < 7×24 h
        assertTrue(SubscriptionWarning.isWarning(sub(at(2026, 11, 13, 23)), now, zone))
        assertFalse(SubscriptionWarning.isWarning(sub(at(2026, 11, 14, 0)), now, zone))
        assertTrue(SubscriptionWarning.isWarning(sub(now - 1), now, zone)) // expired
        assertFalse(SubscriptionWarning.isWarning(sub(null), now, zone))
    }

    @Test fun eightyPercentUsed() {
        assertTrue(SubscriptionWarning.isWarning(sub(null, 80, 100), now, zone))
        assertFalse(SubscriptionWarning.isWarning(sub(null, 79, 100), now, zone))
        assertFalse(SubscriptionWarning.isWarning(sub(null, 80, 0), now, zone))
        assertFalse(SubscriptionWarning.isWarning(sub(null, 80, null), now, zone))
    }
}
