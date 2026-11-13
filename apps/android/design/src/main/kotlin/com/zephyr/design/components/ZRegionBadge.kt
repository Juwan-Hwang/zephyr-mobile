package com.zephyr.design.components

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.theme.ZTypography

/**
 * Region code chip ("SG", "HK"): monospaced letters in a hairline box — the prototype replaces emoji flags
 * (which render inconsistently and are politically sensitive for some regions) with ISO codes.
 */
@Composable
fun ZRegionBadge(code: String, modifier: Modifier = Modifier, large: Boolean = false, active: Boolean = false) {
    val c = ZTheme.colors
    Box(
        modifier
            .defaultMinSize(minWidth = if (large) 40.dp else 28.dp, minHeight = if (large) 0.dp else 20.dp)
            .border(1.dp, if (active) c.accent else c.hairlineStrong, if (large) ZTheme.shapes.control else BadgeShape)
            .padding(horizontal = if (large) 6.dp else 5.dp, vertical = if (large) 5.dp else 0.dp),
        contentAlignment = Alignment.Center,
    ) {
        ZText(code.uppercase(), style = if (large) ZTheme.type.mono else BadgeText, color = if (active) c.accent else c.text2, maxLines = 1)
    }
}

private val BadgeShape = RoundedCornerShape(5.dp)
private val BadgeText = ZTypography.default.monoSmall.copy(fontSize = 10.5.sp, lineHeight = 12.sp, fontWeight = FontWeight.SemiBold)
