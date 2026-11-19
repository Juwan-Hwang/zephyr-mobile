package com.zephyr.app.ui.subs

import com.zephyr.engine.Subscription
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Contract §16.e ④ (U13): a subscription is shown in amber (usage bar and expiry text, subscriptions page and home
 * alike) when it has expired or expires within 7 calendar days, or when `usedBytes / totalBytes ≥ 80%`. No total
 * (or 0) → usage is not judged. Prototype: Orbit 3 days / 88% → amber; Nebula 26 days / 57% → not.
 */
object SubscriptionWarning {
    const val DAYS = 7L
    const val USED_FRACTION = 0.8

    fun isWarning(s: Subscription, now: Long, zone: ZoneId = ZoneId.systemDefault()): Boolean =
        expiresSoon(s.expiresAt, now, zone) || mostlyUsed(s.usedBytes, s.totalBytes)

    fun expiresSoon(expiresAt: Long?, now: Long, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val exp = expiresAt ?: return false
        if (exp <= now) return true
        val days = ChronoUnit.DAYS.between(Instant.ofEpochMilli(now).atZone(zone).toLocalDate(), Instant.ofEpochMilli(exp).atZone(zone).toLocalDate())
        return days <= DAYS
    }

    fun mostlyUsed(used: Long?, total: Long?): Boolean {
        if (used == null || total == null || total <= 0) return false
        return used.toDouble() / total >= USED_FRACTION
    }
}
