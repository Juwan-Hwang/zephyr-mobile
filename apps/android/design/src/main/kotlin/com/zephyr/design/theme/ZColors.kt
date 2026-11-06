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
        /** Single source of truth: tokens/mobile.json `screen.*` (A's pipeline). Only derived alphas are computed here. */
        val dark = from(com.zephyr.design.tokens.ZColors.Dark)
        val light = from(com.zephyr.design.tokens.ZColors.Light)

        private fun from(t: com.zephyr.design.tokens.ZColors) = ZThemeColors(
            isDark = t.isDark,
            bg = t.screenBg,
            surface1 = t.screenS1,
            surface2 = t.screenS2,
            surface3 = t.screenS3,
            surface4 = t.screenS4,
            hairline = t.screenHl,
            hairlineStrong = t.screenHl2,
            text1 = t.screenT1,
            text2 = t.screenT2,
            text3 = t.screenT3,
            text4 = t.screenT4,
            accent = if (t.isDark) ZAccent.BLUE.darkVariant() else ZAccent.BLUE.color,
            accentSoft = (if (t.isDark) ZAccent.BLUE.darkVariant() else ZAccent.BLUE.color).copy(alpha = 0.16f),
            onAccent = Color.White,
            connected = t.screenGreen,
            warning = t.screenAmber,
            warningSoft = t.screenAmberA,
            danger = t.screenRed,
            download = t.colorDownload,
            upload = t.screenUp,
            glass = t.screenGlass,
            scrim = t.screenCmdBg,
            onPrimaryButton = t.screenOnPrimary,
            primaryButton = t.screenPrimary,
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

/** Latency colour per tokens: quiet below [com.zephyr.design.tokens.ZLatency.slow], amber at/above, red only on timeout. */
fun ZThemeColors.latency(ms: Int?): Color = when {
    ms == null -> text3
    ms < 0 -> danger
    ms >= com.zephyr.design.tokens.ZLatency.slow -> warning
    else -> text2
}
