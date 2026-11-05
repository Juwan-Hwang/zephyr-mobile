package com.zephyr.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.geometry.Offset

// AUTO-GENERATED — DO NOT EDIT — Source: packages/tokens/src/*.json
// Run: npx style-dictionary build --config=packages/tokens/config.js

object AppColors {
    val ColorBlue500: Color = Color(0xFF007AFFFF)
    val ColorBlue600: Color = Color(0xFF2563EBFF)
    val ColorGreen500: Color = Color(0xFF34C759FF)
    val ColorGreen600: Color = Color(0xFF16A34AFF)
    val ColorOrange500: Color = Color(0xFFFF9500FF)
    val ColorOrange600: Color = Color(0xFFEA580CFF)
    val ColorPink500: Color = Color(0xFFFF2D55FF)
    val ColorPink600: Color = Color(0xFFDB2777FF)
    val ColorPurple500: Color = Color(0xFFAF52DEFF)
    val ColorPurple600: Color = Color(0xFF9333EAFF)
    val ColorRed400: Color = Color(0xFFF87171FF)
    val ColorRed500: Color = Color(0xFFEF4444FF)
    val ColorRed600: Color = Color(0xFFDC2626FF)
    val ColorAmber500: Color = Color(0xFFF59E0BFF)
    val ColorAmber600: Color = Color(0xFFD97706FF)
    val ColorEmerald400: Color = Color(0xFF4ADE80FF)
    val ColorEmerald500: Color = Color(0xFF22C55EFF)
    val ColorEmerald600: Color = Color(0xFF16A34AFF)
    val ColorSky400: Color = Color(0xFF38BDF8FF)
    val ColorSky500: Color = Color(0xFF0EA5E9FF)
    val ColorZinc100: Color = Color(0xFFF4F4F5FF)
    val ColorZinc200: Color = Color(0xFFE4E4E7FF)
    val ColorZinc300: Color = Color(0xFFD4D4D8FF)
    val ColorZinc400: Color = Color(0xFFA1A1AAFF)
    val ColorZinc500: Color = Color(0xFF71717AFF)
    val ColorZinc600: Color = Color(0xFF52525BFF)
    val ColorDanger: Color = Color(0xFFEF4444FF)
    val ColorDangerLight: Color = Color(0xFFDC2626FF)
    val ColorWarning: Color = Color(0xFFF59E0BFF)
    val ColorWarningLight: Color = Color(0xFFD97706FF)
    val ColorSuccess: Color = Color(0xFF4ADE80FF)
    val ColorSuccessLight: Color = Color(0xFF16A34AFF)
    val ColorInfo: Color = Color(0xFF38BDF8FF)
    val ColorInfoLight: Color = Color(0xFF2563EBFF)
    val TextPrimary: Color = Color(1.000f, 1.000f, 1.000f, 0.95f)
    val TextPrimaryLight: Color = Color(0.094f, 0.094f, 0.110f, 0.95f)
    val TextSecondary: Color = Color(1.000f, 1.000f, 1.000f, 0.6f)
    val TextSecondaryLight: Color = Color(0.094f, 0.094f, 0.110f, 0.65f)
    val TextTertiary: Color = Color(1.000f, 1.000f, 1.000f, 0.4f)
    val TextTertiaryLight: Color = Color(0.094f, 0.094f, 0.110f, 0.4f)
    val TextMuted: Color = Color(0xFF71717AFF)
    val TextDanger: Color = Color(0xFFEF4444FF)
    val TextDangerLight: Color = Color(0xFFDC2626FF)
    val TextWarning: Color = Color(0xFFF59E0BFF)
    val TextWarningLight: Color = Color(0xFFD97706FF)
    val TextSuccess: Color = Color(0xFF4ADE80FF)
    val TextSuccessLight: Color = Color(0xFF16A34AFF)
    val TextInfo: Color = Color(0xFF38BDF8FF)
    val TextInfoLight: Color = Color(0xFF2563EBFF)
    val TextOnAccent: Color = Color(0xFFFFFFFFFF)
    val TextBadge: Color = Color(1.000f, 1.000f, 1.000f, 0.6f)
    val TextBadgeLight: Color = Color(0.094f, 0.094f, 0.110f, 0.65f)
    val BgSecondary: Color = Color(0.047f, 0.047f, 0.063f, 0.55f)
    val BgSecondaryLight: Color = Color(0.000f, 0.000f, 0.000f, 0.04f)
    val BgTertiary: Color = Color(0.047f, 0.047f, 0.063f, 0.5f)
    val BgTertiaryLight: Color = Color(0.000f, 0.000f, 0.000f, 0.06f)
    val BgSubtle: Color = Color(1.000f, 1.000f, 1.000f, 0.03f)
    val BgSubtleLight: Color = Color(0.000f, 0.000f, 0.000f, 0.03f)
    val BgMuted: Color = Color(1.000f, 1.000f, 1.000f, 0.05f)
    val BgMutedLight: Color = Color(0.000f, 0.000f, 0.000f, 0.05f)
    val BgInput: Color = Color(0.000f, 0.000f, 0.000f, 0.4f)
    val BgInputLight: Color = Color(1.000f, 1.000f, 1.000f, 0.8f)
    val BgElevated: Color = Color(0.094f, 0.094f, 0.106f, 0.97f)
    val BgElevatedLight: Color = Color(0xFFFFFFFFFF)
    val BgOverlay: Color = Color(0.000f, 0.000f, 0.000f, 0.4f)
    val BgOverlayLight: Color = Color(0.000f, 0.000f, 0.000f, 0.25f)
    val BorderPrimary: Color = Color(1.000f, 1.000f, 1.000f, 0.1f)
    val BorderPrimaryLight: Color = Color(0.000f, 0.000f, 0.000f, 0.15f)
    val BorderSubtle: Color = Color(1.000f, 1.000f, 1.000f, 0.05f)
    val BorderSubtleLight: Color = Color(0.118f, 0.161f, 0.231f, 0.1f)
    val BorderDefault: Color = Color(1.000f, 1.000f, 1.000f, 0.1f)
    val BorderDefaultLight: Color = Color(0.118f, 0.161f, 0.231f, 0.14f)
    val BorderStrong: Color = Color(1.000f, 1.000f, 1.000f, 0.2f)
    val BorderStrongLight: Color = Color(0.118f, 0.161f, 0.231f, 0.2f)
}

object AppSpacing {
    val Space0 = 0.dp
    val Space1 = 4.dp
    val Space2 = 6.dp
    val Space3 = 8.dp
    val Space4 = 12.dp
    val Space5 = 16.dp
    val Space6 = 24.dp
    val Space7 = 32.dp
    val Space8 = 48.dp
}

object AppRadius {
    val RadiusSm = 8.dp
    val RadiusMd = 16.dp
    val RadiusLg = 24.dp
    val RadiusFull = 9999.dp
    val RadiusDropdownOption = 18.dp
}

object AppFontSize {
    val FontSize2xs = 10.sp
    val FontSizeXs = 12.sp
    val FontSizeSm = 14.sp
    val FontSizeBase = 16.sp
    val FontSizeLg = 18.sp
    val FontSizeXl = 20.sp
    val FontSize2xl = 24.sp
    val FontSize3xl = 30.sp
    val FontSize4xl = 36.sp
}

data class ShadowData(val offsetX: Dp, val offsetY: Dp, val blurRadius: Dp, val spread: Dp = 0.dp, val color: Color)

object AppShadow {
    val ShadowSm = ShadowData(offsetX = 0.dp, offsetY = 4.dp, blurRadius = 20.dp, spread = 0.dp, color = Color(0.000f, 0.000f, 0.000f, 0.2f))
    val ShadowMd = ShadowData(offsetX = 0.dp, offsetY = 10.dp, blurRadius = 40.dp, spread = 0.dp, color = Color(0.000f, 0.000f, 0.000f, 0.35f))
    val ShadowPlugin = ShadowData(offsetX = 0.dp, offsetY = 24.dp, blurRadius = 48.dp, spread = -12.dp, color = Color(0.000f, 0.000f, 0.000f, 0.5f))
    val ShadowDropdown = ShadowData(offsetX = 10.dp, offsetY = 10.dp, blurRadius = 10.dp, spread = 0.dp, color = Color(0.000f, 0.000f, 0.000f, 0.1f))
    val ShadowDropdownLight = ShadowData(offsetX = 10.dp, offsetY = 10.dp, blurRadius = 10.dp, spread = 0.dp, color = Color(0.000f, 0.000f, 0.000f, 0.08f))
    // inset 0 0 0 1px rgba(255, 255, 255, 0.2), 0 0 0 0.5px rgba(0, 0, 0, 0.2), 0 8px 40px rgba(0, 0, 0, 0.55) (light: inset 0 0 0 1px rgba(255, 255, 255, 0.2), 0 0 0 0.5px rgba(0, 0, 0, 0.2), 0 8px 40px rgba(0, 0, 0, 0.25))
    // 0 0 8px var(--color-accent-glow)
}

object AppTime {
    val TimeMicro = 100  // ms
    val TimeStandard = 210  // ms
    val TimeFast = 400  // ms
    val TimeDropdown = 150  // ms
    val TimePage = 300  // ms
}

object AppEasing {
    val EasingEaseIn = androidx.compose.animation.core.CubicBezierEasing(0.42f, 0f, 1f, 1f)
    val EasingEaseOut = androidx.compose.animation.core.CubicBezierEasing(0f, 0f, 0.58f, 1f)
    val EasingSpring = androidx.compose.animation.core.CubicBezierEasing(0.16f, 1f, 0.3f, 1f)
    val EasingSmooth = androidx.compose.animation.core.CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f)
}

object AppZIndex {
    val ZIndexBase = 0
    val ZIndexContent = 10
    val ZIndexSticky = 200
    val ZIndexDropdown = 500
    val ZIndexPopover = 700
    val ZIndexOverlay = 800
    val ZIndexModal = 1000
    val ZIndexToast = 1100
}

object AppGlass {
    val GlassBlur = 16.dp
}

object AppBrightness {
    val BrightnessDark = 0.88f
    val BrightnessLight = 0.95f
}

object AppButton {
    val gap = 6.dp
    val paddingY = 8.dp
    val paddingX = 16.dp
    val radius = 24.dp
    val fontSize = 10.sp
    val weight = FontWeight.W700
    val tracking = 0.05.sp
    // transform: uppercase
}

object AppInput {
    val radius = 16.dp
    // padding: 16px 8px
}

object AppCard {
    val radius = 24.dp
    // blur: blur(16px)
}

object AppBadge {
    val radius = 8.dp
    // padding: 0.125rem 0.375rem
    val fontSize = 10.sp
}

object AppDropdown {
    val radius = 24.dp
    // padding: 8px 12px
    val itemRadius = 18.dp
}

object AppSwitch {
    val radius = 9999.dp
    val width = 40.dp
    val height = 24.dp
}

object AppModal {
    val radius = 24.dp
}

object AppPanel {
    val radius = 24.dp
}

object AppAccent {
    data class AccentTheme(val primary: Color, val glow: Color, val rgb: String)
    val blue = AccentTheme(Color(0xFF007AFF), Color(0x33007AFF), "0, 122, 255")
    val green = AccentTheme(Color(0xFF34C759), Color(0x3334C759), "52, 199, 89")
    val orange = AccentTheme(Color(0xFFFF9500), Color(0x33FF9500), "255, 149, 0")
    val pink = AccentTheme(Color(0xFFFF2D55), Color(0x33FF2D55), "255, 45, 85")
    val purple = AccentTheme(Color(0xFFAF52DE), Color(0x33AF52DE), "175, 82, 222")
}
