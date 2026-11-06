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
    val selection = remember(colors) { TextSelectionColors(colors.accent, colors.accent.copy(alpha = 0.3f)) }
    CompositionLocalProvider(
        LocalColors provides colors,
        LocalZColors provides if (dark) ZColors.Dark else ZColors.Light,
        LocalType provides ZTypography.default,
        LocalSpacing provides ZSpacing(),
        LocalShapes provides ZShapes(),
        LocalTextSelectionColors provides selection,
        LocalIndication provides ZIndication,
        content = content,
    )
}
