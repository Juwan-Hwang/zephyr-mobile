package com.zephyr.app.ui.common

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.app.R
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme

/** Brand lockup: Z glyph + "Zephyr" wordmark (design/prototype/brand/app-lockup.svg). Never mirrored in RTL. */
@Composable
fun ZephyrLockup(
    modifier: Modifier = Modifier,
    tint: androidx.compose.ui.graphics.Color = ZTheme.colors.text1,
    style: LockupStyle = LockupStyle.Large,
) {
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.ui.platform.LocalLayoutDirection provides androidx.compose.ui.unit.LayoutDirection.Ltr,
    ) { Lockup(modifier, tint, style) }
}

/**
 * [Large]: onboarding / today card (19sp bold). [Home]: the home header wordmark, ≈15sp semibold so it sits under the
 * status title instead of competing with it (spec §9.8, review And-5; same as iOS).
 */
enum class LockupStyle(val glyph: Dp, val gap: Dp, val text: TextUnit, val weight: FontWeight, val tracking: TextUnit) {
    Large(20.dp, 4.dp, 19.sp, FontWeight.Bold, (-0.2).sp),
    Home(16.dp, 4.dp, 15.sp, FontWeight.SemiBold, (-0.1).sp),
}

@Composable
private fun Lockup(modifier: Modifier, tint: androidx.compose.ui.graphics.Color, s: LockupStyle) {
    Row(modifier.clearAndSetSemantics { contentDescription = "Zephyr" }, verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(R.drawable.ic_stat_zephyr), null, Modifier.size(s.glyph), colorFilter = ColorFilter.tint(tint))
        Spacer(Modifier.width(s.gap))
        ZText("Zephyr", style = ZTheme.type.headline.copy(fontWeight = s.weight, fontSize = s.text, letterSpacing = s.tracking), color = tint)
    }
}
