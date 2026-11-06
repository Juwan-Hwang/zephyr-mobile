package com.zephyr.design.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import com.zephyr.design.tokens.ZAccent

/**
 * Semantic palette. Values come from the prototype's `:root` / `.device.light` (design/prototype/index.html),
 * which itself follows vendor/zephyr/packages/tokens (dark first, light as override, text hierarchy by alpha).
 *
 * Shared values (download/upload, accents, motion, latency thresholds) come from generated tokens (tokens/generated/android);
 * the prototype-only surface palette stays here until tokens/mobile.json carries it.
 */
@Immutable
data class ZThemeColors(
    val isDark: Boolean,
    val bg: Color,
    val surface1: Color,
    val surface2: Color,
    val surface3: Color,
    val surface4: Color,
    val hairline: Color,
    val hairlineStrong: Color,
    val text1: Color,
    val text2: Color,
    val text3: Color,
    val text4: Color,
    val accent: Color,
    val accentSoft: Color,
    val onAccent: Color,
    val connected: Color,
    val warning: Color,
    val warningSoft: Color,
    val danger: Color,
    val download: Color,
    val upload: Color,
    val glass: Color,
    val scrim: Color,
    val onPrimaryButton: Color,
    val primaryButton: Color,
) {
    fun withAccent(accent: ZAccent): ZThemeColors {
        val c = if (isDark) accent.darkVariant() else accent.color
        return copy(accent = c, accentSoft = c.copy(alpha = 0.16f))
    }

    companion object {
        val dark = ZThemeColors(
            isDark = true,
            bg = Color(0xFF000000),
            surface1 = Color(0xFF0C0C0E),
            surface2 = Color(0xFF141417),
            surface3 = Color(0xFF1D1D21),
            surface4 = Color(0xFF26262B),
            hairline = Color(0x13FFFFFF),        // .075
            hairlineStrong = Color(0x21FFFFFF),  // .13
            text1 = Color(0xF2FFFFFF),           // .95
            text2 = Color(0x99FFFFFF),           // .60
            text3 = Color(0x66FFFFFF),           // .40
            text4 = Color(0x33FFFFFF),           // .20
            accent = Color(0xFF0A84FF),
            accentSoft = Color(0x290A84FF),
            onAccent = Color.White,
            connected = Color(0xFF30D158),
            warning = Color(0xFFFFD60A),
            warningSoft = Color(0x1FFFD60A),
            danger = Color(0xFFFF453A),
            download = Color(0xFF0A84FF),
            upload = Color(0xFFFF6B6B),
            glass = Color(0xD11C1C20),           // rgba(28,28,32,.82)
            scrim = Color(0x99000000),
            onPrimaryButton = Color(0xFF000000),
            primaryButton = Color(0xFFF2F2F2),
        )

        val light = ZThemeColors(
            isDark = false,
            bg = Color(0xFFF2F2F7),
            surface1 = Color(0xFFFFFFFF),
            surface2 = Color(0xFFFFFFFF),
            surface3 = Color(0xFFE9E9EE),
            surface4 = Color(0xFFDCDCE1),
            hairline = Color(0x12000000),        // .07
            hairlineStrong = Color(0x1F000000),  // .12
            text1 = Color(0xE6000000),           // .90
            text2 = Color(0x94000000),           // .58
            text3 = Color(0x66000000),           // .40
            text4 = Color(0x2E000000),           // .18
            accent = Color(0xFF007AFF),
            accentSoft = Color(0x29007AFF),
            onAccent = Color.White,
            connected = Color(0xFF34C759),
            warning = Color(0xFFFF9F0A),
            warningSoft = Color(0x1FFF9F0A),
            danger = Color(0xFFFF3B30),
            download = Color(0xFF007AFF),
            upload = Color(0xFFFF5E57),
            glass = Color(0xD1FFFFFF),
            scrim = Color(0x52000000),
            onPrimaryButton = Color(0xFFFFFFFF),
            primaryButton = Color(0xFF111114),
        )
    }
}

/** Prototype dark mode uses the iOS dark-variant system colours for accents. */
fun ZAccent.darkVariant(): Color = when (this) {
    ZAccent.BLUE -> Color(0xFF0A84FF)
    ZAccent.GREEN -> Color(0xFF30D158)
    ZAccent.ORANGE -> Color(0xFFFF9F0A)
    ZAccent.PINK -> Color(0xFFFF375F)
}

/** Latency → colour bucket used by pills and node rows. */
fun ZThemeColors.latency(ms: Int?): Color = when {
    ms == null -> text3
    ms < 0 -> danger
    ms <= 200 -> text2
    ms <= 500 -> warning
    else -> danger
}
