package com.zephyr.design.format

import android.content.res.Resources
import android.icu.text.CompactDecimalFormat
import com.zephyr.design.R
import java.util.Locale
import kotlin.math.abs

/**
 * Number/time formatting shared by every screen. Numeric formats are locale-neutral; anything with words
 * (relative time, expiry, compact units) takes [Resources] so it follows the App's language.
 * Allocation-light and safe to call during composition (pass `LocalResources.current`).
 */
object ZFormat {
    /** 2_800_000 → ("2.8", "MB"); 195_000 → ("195", "KB"). Decimal units like the prototype. */
    fun rate(bps: Long): Pair<String, String> = bytes(bps)

    fun bytes(b: Long): Pair<String, String> {
        val v = abs(b).toDouble()
        return when {
            v >= 1e12 -> one(v / 1e12) to "TB"
            v >= 1e9 -> one(v / 1e9) to "GB"
            v >= 1e6 -> one(v / 1e6) to "MB"
            v >= 1e3 -> (v / 1e3).toLong().toString() to "KB"
            else -> v.toLong().toString() to "B"
        }
    }

    fun bytesText(b: Long): String = bytes(b).let { "${it.first} ${it.second}" }

    private fun one(v: Double): String = if (v >= 100) v.toLong().toString() else String.format(Locale.US, "%.1f", v)

    /** 13109802 → "13,109,802". */
    fun grouped(n: Long): String = String.format(Locale.US, "%,d", n)

    /**
     * Compact count for stat tiles. Myriad languages (zh): 13_109_802 → "1,311 万", 103_606_731 → "1.04 亿",
     * 512 → "512". Others: the locale's short form, 13_109_802 → "13M". Below 10 000 always the full number.
     */
    fun compact(res: Resources, n: Long): String = when {
        n < 10_000 -> grouped(n)
        !res.getBoolean(R.bool.common_number_myriad) -> short(res, n)
        n >= 100_000_000 -> String.format(Locale.US, "%.2f %s", n / 1e8, res.getString(R.string.common_unit_yi))
        else -> "${grouped(Math.round(n / 1e4))} ${res.getString(R.string.common_unit_wan)}"
    }

    /** Chip count: 3_118_402 → "312 万" (myriad) / "3.1M". */
    fun chip(res: Resources, n: Long): String =
        if (res.getBoolean(R.bool.common_number_myriad)) "${Math.round(n / 1e4)} ${res.getString(R.string.common_unit_wan)}" else short(res, n)

    private fun short(res: Resources, n: Long): String =
        CompactDecimalFormat.getInstance(res.configuration.locales[0], CompactDecimalFormat.CompactStyle.SHORT).format(n)

    /** 8047000 ms → "2:14:07"; under an hour "0:04:07" (prototype `renderDur`, iOS ZFormat.duration; audit #208 U20). */
    fun duration(ms: Long): String {
        val s = (ms / 1000).coerceAtLeast(0)
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        return String.format(Locale.US, "%d:%02d:%02d", h, m, sec)
    }

    /**
     * Relative past time: "Just now" / "5 min ago" / "2h ago" / "3d ago" (zh "刚刚" / "5 分钟前" …).
     * [inline] lower-cases "just now" for use inside a sentence.
     */
    fun ago(res: Resources, at: Long, now: Long, inline: Boolean = false): String {
        val d = (now - at).coerceAtLeast(0) / 1000
        fun q(id: Int, n: Long) = n.toInt().let { res.getQuantityString(id, it, it) }
        return when {
            d < 60 -> res.getString(if (inline) R.string.common_time_just_now_inline else R.string.common_time_just_now)
            d < 3600 -> q(R.plurals.common_time_minutes_ago, d / 60)
            d < 86_400 -> q(R.plurals.common_time_hours_ago, d / 3600)
            else -> q(R.plurals.common_time_days_ago, d / 86_400)
        }
    }

    /**
     * Expiry: "Expires in 26 days" / "Expires tomorrow" / "Expires today" / "Expired" (zh "26 天后到期" …). Days are
     * calendar days in [zone] (audit #208 U16), so 23:00 → 01:00 the next day is "tomorrow", not "today".
     * Expiries 2–6 days out read as the weekday with [weekday] (home card, review H-P2-7), otherwise as the month and
     * day ("Expires Nov 9" / "11月9日到期", prototype subscriptions page; iOS ZFormat.expiry).
     */
    fun expires(res: Resources, at: Long, now: Long, weekday: Boolean = false, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String {
        if (at <= now) return res.getString(R.string.common_expiry_expired)
        val due = java.time.Instant.ofEpochMilli(at).atZone(zone).toLocalDate()
        val days = java.time.temporal.ChronoUnit.DAYS.between(java.time.Instant.ofEpochMilli(now).atZone(zone).toLocalDate(), due)
        return when {
            days <= 0L -> res.getString(R.string.common_expiry_today)
            days == 1L -> res.getString(R.string.common_expiry_tomorrow)
            days < 7 && weekday -> res.getString(R.string.common_expiry_weekday, res.getStringArray(R.array.common_weekdays)[due.dayOfWeek.value - 1])
            days < 7 -> res.getString(R.string.common_expiry_date, monthDay(res, due))
            else -> days.toInt().let { res.getQuantityString(R.plurals.common_expiry_in_days, it, it) }
        }
    }

    /** "11月9日" / "Nov 9" / "9 нояб." in the App's language, digits kept Latin like every other figure. */
    fun monthDay(res: Resources, date: java.time.LocalDate): String {
        val locale = res.configuration.locales[0]
        val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMd")
        return java.time.format.DateTimeFormatter.ofPattern(pattern, locale)
            .withDecimalStyle(java.time.format.DecimalStyle.STANDARD).format(date)
    }

    fun micros(us: Long): String = if (us < 1000) String.format(Locale.US, "%.2f ms", us / 1000.0) else String.format(Locale.US, "%.1f ms", us / 1000.0)
}
