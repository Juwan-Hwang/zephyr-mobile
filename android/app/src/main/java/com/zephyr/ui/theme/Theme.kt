package com.zephyr.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.sp

// ── Accent theme state ──────────────────────────────────────────────────

/**
 * Global accent theme state, persisted across recompositions.
 * Default: purple (matching desktop default)
 */
object AccentThemeState {
    var current by mutableStateOf(AppAccent.purple)
        private set

    fun setTheme(theme: AppAccent.AccentTheme) {
        current = theme
    }

    fun setThemeByName(name: String) {
        current = when (name) {
            "blue" -> AppAccent.blue
            "green" -> AppAccent.green
            "orange" -> AppAccent.orange
            "pink" -> AppAccent.pink
            "purple" -> AppAccent.purple
            else -> AppAccent.purple
        }
    }
}

// ── Color scheme builders ───────────────────────────────────────────────

private fun buildDarkColorScheme(accent: AppAccent.AccentTheme): ColorScheme {
    return darkColorScheme(
        primary = accent.primary,
        onPrimary = AppColors.TextOnAccent,
        primaryContainer = accent.primary.copy(alpha = 0.15f),
        onPrimaryContainer = accent.primary,
        secondary = AppColors.ColorSky400,
        onSecondary = Color.White,
        secondaryContainer = AppColors.ColorSky400.copy(alpha = 0.15f),
        onSecondaryContainer = AppColors.ColorSky400,
        tertiary = AppColors.ColorPurple500,
        background = Color(0xFF0C0C10),       // rgb(12,12,16) — dark bg base
        onBackground = AppColors.TextPrimary,
        surface = AppColors.BgSecondary,       // glass card bg
        onSurface = AppColors.TextPrimary,
        surfaceVariant = AppColors.BgMuted,    // subtle bg
        onSurfaceVariant = AppColors.TextSecondary,
        outline = AppColors.BorderDefault,
        outlineVariant = AppColors.BorderSubtle,
        error = AppColors.ColorDanger,
        onError = Color.White,
        errorContainer = AppColors.ColorDanger.copy(alpha = 0.12f),
        onErrorContainer = AppColors.ColorDanger,
        inverseSurface = AppColors.BgElevated,
        inverseOnSurface = AppColors.TextPrimary,
        inversePrimary = accent.primary,
        surfaceTint = accent.primary.copy(alpha = 0.08f),
    )
}

private fun buildLightColorScheme(accent: AppAccent.AccentTheme): ColorScheme {
    return lightColorScheme(
        primary = accent.primary,
        onPrimary = AppColors.TextOnAccent,
        primaryContainer = accent.primary.copy(alpha = 0.12f),
        onPrimaryContainer = accent.primary,
        secondary = AppColors.ColorBlue600,
        onSecondary = Color.White,
        secondaryContainer = AppColors.ColorBlue600.copy(alpha = 0.12f),
        onSecondaryContainer = AppColors.ColorBlue600,
        tertiary = AppColors.ColorPurple600,
        background = Color(0xFFF8FAFC),       // rgb(248,250,252) — light bg base
        onBackground = AppColors.TextPrimaryLight,
        surface = AppColors.BgSecondaryLight,
        onSurface = AppColors.TextPrimaryLight,
        surfaceVariant = AppColors.BgMutedLight,
        onSurfaceVariant = AppColors.TextSecondaryLight,
        outline = AppColors.BorderPrimaryLight,
        outlineVariant = AppColors.BorderSubtleLight,
        error = AppColors.ColorDangerLight,
        onError = Color.White,
        errorContainer = AppColors.ColorDangerLight.copy(alpha = 0.12f),
        onErrorContainer = AppColors.ColorDangerLight,
        inverseSurface = AppColors.BgElevatedLight,
        inverseOnSurface = AppColors.TextPrimaryLight,
        inversePrimary = accent.primary,
        surfaceTint = accent.primary.copy(alpha = 0.06f),
    )
}

// ── Zephyr theme composable ─────────────────────────────────────────────

@Composable
fun ZephyrTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val accent = AccentThemeState.current
    val colorScheme = if (darkTheme) buildDarkColorScheme(accent) else buildLightColorScheme(accent)

    // Make status/nav bars transparent for immersive glass effect
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Color.Transparent.toArgb()
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = ZephyrTypography,
        content = content,
    )
}

// ── Typography ──────────────────────────────────────────────────────────

private val ZephyrTypography = Typography(
    displayLarge = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.ExtraLight,
        letterSpacing = androidx.compose.ui.unit.TextUnit.Unspecified,
    ),
    headlineLarge = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Light,
    ),
    headlineMedium = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Light,
    ),
    headlineSmall = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
    ),
    titleLarge = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
    ),
    titleMedium = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
    ),
    titleSmall = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
        fontSize = 14.sp,
    ),
    bodyLarge = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Normal,
    ),
    bodyMedium = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Normal,
    ),
    bodySmall = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Normal,
        fontSize = 12.sp,
    ),
    labelLarge = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
        letterSpacing = 0.05.sp,
    ),
    labelMedium = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
        fontSize = 10.sp,
        letterSpacing = 0.05.sp,
    ),
    labelSmall = androidx.compose.ui.text.TextStyle(
        fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
        fontSize = 9.sp,
        letterSpacing = 0.1.sp,
    ),
)
