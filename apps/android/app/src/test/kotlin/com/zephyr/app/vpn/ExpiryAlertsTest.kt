package com.zephyr.app.vpn

import com.zephyr.engine.Subscription
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

/** Contract §16.e ⑤ (U29): once per subscription per expiresAt, 3 calendar days before at 10:00 local. */
class ExpiryAlertsTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private fun at(m: Int, d: Int, h: Int, min: Int = 0) = LocalDateTime.of(2026, m, d, h, min).atZone(zone).toInstant().toEpochMilli()
    private fun sub(id: String, exp: Long?) = Subscription(id, id, nodeCount = 1, expiresAt = exp)

    @Test fun firesThreeCalendarDaysBeforeAtTen() {
        assertEquals(at(11, 6, 10), ExpiryAlerts.fireAt(at(11, 9, 0, 30), zone))
        assertEquals(at(11, 6, 10), ExpiryAlerts.fireAt(at(11, 9, 23, 59), zone))
    }

    @Test fun plansNextAndNotifiesDue() {
        val orbit = sub("orbit", at(11, 9, 8))
        val nebula = sub("nebula", at(12, 2, 8))
        val p = ExpiryAlerts.plan(listOf(orbit, nebula, sub("local", null)), at(11, 1, 9), zone, emptySet())
        assertTrue(p.now.isEmpty())
        assertEquals(at(11, 6, 10), p.nextAt)
        val q = ExpiryAlerts.plan(listOf(orbit, nebula), at(11, 6, 10), zone, emptySet())
        assertEquals(listOf(orbit), q.now)
        assertEquals(at(11, 29, 10), q.nextAt)
    }

    @Test fun learntInsideWindowNotifiesNowButNeverWhenExpired() {
        val soon = sub("a", at(11, 7, 12))
        assertEquals(listOf(soon), ExpiryAlerts.plan(listOf(soon), at(11, 6, 15), zone, emptySet()).now)
        val gone = sub("b", at(11, 6, 12))
        val p = ExpiryAlerts.plan(listOf(gone), at(11, 6, 15), zone, emptySet())
        assertTrue(p.now.isEmpty()); assertNull(p.nextAt)
    }

    @Test fun oncePerExpiryAndAgainAfterRenewal() {
        val s = sub("a", at(11, 7, 12))
        val sent = setOf(ExpiryAlerts.key(s))
        assertTrue(ExpiryAlerts.plan(listOf(s), at(11, 6, 15), zone, sent).now.isEmpty())
        val renewed = s.copy(expiresAt = at(12, 7, 12))
        val p = ExpiryAlerts.plan(listOf(renewed), at(11, 6, 15), zone, sent)
        assertTrue(p.now.isEmpty())
        assertEquals(at(12, 4, 10), p.nextAt)
    }
}
