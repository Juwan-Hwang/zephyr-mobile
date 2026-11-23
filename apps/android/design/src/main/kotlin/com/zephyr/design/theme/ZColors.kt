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
    /** §9.1 accent roles (tokens `accent.*.text` / `fill` / `on-fill`): [accent] = base (toggles, progress, glow, selection strokes);
     *  [accentText] = foreground small text, links, index rail, search highlight, icons; [accentFill] + [onAccentFill] = accent buttons / pills. */
    val accentText: Color,
    val accentFill: Color,
    val onAccentFill: Color,
    val connected: Color,
    val warning: Color,
    val warningSoft: Color,
    val danger: Color,
    /** Status colours as TEXT (§9.1, tokens `screen.*-text`): light #B25000 / #1F7A35 / #D70015, dark = base. [connected] / [warning] / [danger] stay for dots, bars and icon fills. */
    val connectedText: Color,
    val warningText: Color,
    val dangerText: Color,
    /** Latency READING text (tokens `latency.slow` / `latency.timeout`). */
    val latencySlow: Color,
    val latencyTimeout: Color,
    val download: Color,
    val upload: Color,
    val glass: Color,
    val scrim: Color,
    /** Neutral t1 pill (tokens `screen.primary` / `on-primary`). No longer used by ZButton.Primary / chips: §9.1 moved those to [accentFill]. */
    val onPrimaryButton: Color,
    val primaryButton: Color,
    /** List swipe actions (tokens `screen.swipe-update` / `swipe-delete` / `on-swipe`, #305): neutral grey update, deep red delete, white label. */
    val swipeUpdate: Color,
    val swipeDelete: Color,
    val onSwipe: Color,
) {
    fun withAccent(accent: ZAccent): ZThemeColors {
        val c = accent.base(isDark)
        return copy(
            accent = c, accentSoft = c.copy(alpha = 0.16f),
            accentText = accent.text(isDark), accentFill = accent.fill(isDark), onAccentFill = accent.onFill(isDark),
        )
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
            accent = ZAccent.BLUE.base(t.isDark),
            accentSoft = ZAccent.BLUE.base(t.isDark).copy(alpha = 0.16f),
            onAccent = Color.White,
            accentText = ZAccent.BLUE.text(t.isDark),
            accentFill = ZAccent.BLUE.fill(t.isDark),
            onAccentFill = ZAccent.BLUE.onFill(t.isDark),
            connected = t.screenGreen,
            warning = t.screenAmber,
            warningSoft = t.screenAmberA,
            danger = t.screenRed,
            connectedText = t.screenGreenText,
            warningText = t.screenAmberText,
            dangerText = t.screenRedText,
            latencySlow = t.latencySlow,
            latencyTimeout = t.latencyTimeout,
            download = t.colorDownload,
            upload = t.screenUp,
            glass = t.screenGlass,
            // Review D-P2-3: prototype `.veil` rgba(0,0,0,.5), light ×0.6 — never the milky command backdrop.
            scrim = Color.Black.copy(alpha = if (t.isDark) 0.5f else 0.3f),
            onPrimaryButton = t.screenOnPrimary,
            primaryButton = t.screenPrimary,
            swipeUpdate = t.screenSwipeUpdate,
            swipeDelete = t.screenSwipeDelete,
            onSwipe = t.screenOnSwipe,
        )
    }
}

/** Latency colour per tokens: quiet below [com.zephyr.design.tokens.ZLatency.slow], amber at/above, red only on timeout. */
fun ZThemeColors.latency(ms: Int?): Color = when {
    ms == null -> text3
    ms < 0 -> latencyTimeout
    ms >= com.zephyr.design.tokens.ZLatency.slow -> latencySlow
    else -> text2
}
