package com.zephyr.design.theme

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.LocalTextSelectionColors
import androidx.compose.foundation.text.selection.TextSelectionColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.zephyr.design.tokens.LocalZColors
import com.zephyr.design.tokens.ZAccent
import com.zephyr.design.tokens.ZColors

@Immutable
data class ZSpacing(
    val xxs: Dp = 4.dp, val xs: Dp = 6.dp, val s: Dp = 8.dp, val m: Dp = 12.dp,
    val l: Dp = 16.dp, val xl: Dp = 24.dp, val xxl: Dp = 32.dp, val xxxl: Dp = 48.dp,
    /** Screen edge inset (prototype: 22pt). */
    val gutter: Dp = 22.dp,
    /** Android touch target (design spec §2: 48dp). */
    val touch: Dp = 48.dp,
    val rowHeight: Dp = 52.dp,
    val rowHeightLarge: Dp = 66.dp,
)

@Immutable
data class ZShapes(
    val control: RoundedCornerShape = RoundedCornerShape(10.dp),
    val surface: RoundedCornerShape = RoundedCornerShape(16.dp),
    val card: RoundedCornerShape = RoundedCornerShape(24.dp),
    val sheet: RoundedCornerShape = RoundedCornerShape(topStart = com.zephyr.design.tokens.ZLayout.sheetRadius, topEnd = com.zephyr.design.tokens.ZLayout.sheetRadius),
    val pill: RoundedCornerShape = RoundedCornerShape(50),
)

/** Motion tokens: micro 120ms, standard 200ms ease-out, slow/page 320ms spring curve (spec §1). */
object ZAnim {
    val EaseOut: Easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)
    val EaseInOut: Easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)
    val Spring: Easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)
    const val MICRO = 120
    const val STANDARD = 200
    const val SLOW = 320

    fun <T> micro(): FiniteAnimationSpec<T> = tween(MICRO, easing = EaseOut)
    fun <T> standard(): FiniteAnimationSpec<T> = tween(STANDARD, easing = EaseOut)
    fun <T> slow(): FiniteAnimationSpec<T> = tween(SLOW, easing = Spring)
    fun <T> bouncy(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.72f, stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow)
}

private val LocalColors = staticCompositionLocalOf { ZThemeColors.dark }
private val LocalType = staticCompositionLocalOf { ZTypography.default }
private val LocalSpacing = staticCompositionLocalOf { ZSpacing() }
private val LocalShapes = staticCompositionLocalOf { ZShapes() }

object ZTheme {
    val colors: ZThemeColors @Composable @ReadOnlyComposable get() = LocalColors.current
    val type: ZTypography @Composable @ReadOnlyComposable get() = LocalType.current
    val spacing: ZSpacing @Composable @ReadOnlyComposable get() = LocalSpacing.current
    val shapes: ZShapes @Composable @ReadOnlyComposable get() = LocalShapes.current
}

/**
 * Root theme. Material is deliberately absent: pages compose Z* components only (spec §6).
 */
@Composable
fun ZephyrTheme(
    dark: Boolean = isSystemInDarkTheme(),
    accent: ZAccent = ZAccent.BLUE,
    content: @Composable () -> Unit,
) {
    val colors = remember(dark, accent) { (if (dark) ZThemeColors.dark else ZThemeColors.light).withAccent(accent) }
    val tokens = if (dark) ZColors.Dark else ZColors.Light
    val indication = remember(tokens.screenPressed) { ZIndication(tokens.screenPressed) }
    val selection = remember(colors) { TextSelectionColors(colors.accent, colors.accent.copy(alpha = 0.3f)) }
    val res = latinDigitResources()
    CompositionLocalProvider(
        androidx.compose.ui.platform.LocalResources provides res,
        LocalColors provides colors,
        LocalZColors provides tokens,
        LocalType provides ZTypography.default,
        LocalSpacing provides ZSpacing(),
        LocalShapes provides ZShapes(),
        LocalTextSelectionColors provides selection,
        LocalIndication provides indication,
        content = content,
    )
}

/**
 * Digits in Arabic, Persian and Urdu: Western (0-9) everywhere, so a count formatted by a string resource
 * ("١٢ ساعة") never sits next to the Western sizes, rates, IPs and grouped counts the UI keeps Latin ("13,098,480").
 * Only the numbering system of resource formatting changes (resource lookup ignores the extension); a numbering
 * system the user picked explicitly (Android 14 regional preferences, `-u-nu-…`) is kept. Other languages get
 * the same Resources object, untouched.
 */
@Composable
@ReadOnlyComposable
private fun latinDigitResources(): android.content.res.Resources {
    val res = androidx.compose.ui.platform.LocalResources.current
    val conf = androidx.compose.ui.platform.LocalConfiguration.current
    val loc = conf.locales[0]
    if (loc.language !in LATIN_DIGIT_LANGUAGES || loc.getUnicodeLocaleType("nu") != null) return res
    val ctx = androidx.compose.ui.platform.LocalContext.current
    return latinCache.getOrPut(conf) {
        runCatching {
            val c = android.content.res.Configuration(conf)
            c.setLocale(java.util.Locale.Builder().setLocale(loc).setUnicodeLocaleKeyword("nu", "latn").build())
            ctx.createConfigurationContext(c).resources
        }.getOrDefault(res)
    }
}

private val LATIN_DIGIT_LANGUAGES = setOf("ar", "fa", "ur")
private val latinCache = java.util.WeakHashMap<android.content.res.Configuration, android.content.res.Resources>()
