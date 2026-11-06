package com.zephyr.design.format

import java.util.Locale
import kotlin.math.abs

/**
 * Number/time formatting shared by every screen (zh-CN copy from the prototype).
 * Pure functions — unit tested, allocation-light, safe to call during composition.
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

    /** Compact Chinese: 13_109_802 → "1,311 万"; 103_606_731 → "1.04 亿"; 512 → "512". */
    fun compactZh(n: Long): String = when {
        n >= 100_000_000 -> String.format(Locale.US, "%.2f 亿", n / 1e8)
        n >= 10_000 -> "${grouped(Math.round(n / 1e4))} 万"
        else -> grouped(n)
    }

    /** 3118402 → "312 万" (chips). */
    fun wan(n: Long): String = "${Math.round(n / 1e4)} 万"

    /** 8047000 ms → "2:14:07". */
    fun duration(ms: Long): String {
        val s = (ms / 1000).coerceAtLeast(0)
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, sec) else String.format(Locale.US, "%d:%02d", m, sec)
    }

    /** Relative past time: "刚刚" / "5 分钟前" / "2 小时前" / "3 天前". */
    fun ago(at: Long, now: Long): String {
        val d = (now - at).coerceAtLeast(0) / 1000
        return when {
            d < 60 -> "刚刚"
            d < 3600 -> "${d / 60} 分钟前"
            d < 86_400 -> "${d / 3600} 小时前"
            else -> "${d / 86_400} 天前"
        }
    }

    /** Expiry: "26 天后到期" / "明天到期" / "已过期". */
    fun expires(at: Long, now: Long): String {
        val days = Math.floorDiv(at - now, 86_400_000L)
        return when {
            at < now -> "已过期"
            days == 0L -> "今天到期"
            days == 1L -> "明天到期"
            else -> "$days 天后到期"
        }
    }

    fun micros(us: Long): String = if (us < 1000) String.format(Locale.US, "%.2f ms", us / 1000.0) else String.format(Locale.US, "%.1f ms", us / 1000.0)
}
