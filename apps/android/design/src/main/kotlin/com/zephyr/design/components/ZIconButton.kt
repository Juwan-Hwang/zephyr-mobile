package com.zephyr.design.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/** 48dp touch target icon button; optional round glass backing (prototype library button). */
@Composable
fun ZIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = ZTheme.colors.text1,
    filled: Boolean = false,
    size: Dp = 48.dp,
    iconSize: Dp = 22.dp,
) {
    val c = ZTheme.colors
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .then(if (filled) Modifier.background(c.glass, CircleShape).border(1.dp, c.hairlineStrong, CircleShape) else Modifier)
            .zPressable(label = contentDescription, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { ZIcon(icon, tint = tint, size = iconSize, contentDescription = contentDescription) }
}
