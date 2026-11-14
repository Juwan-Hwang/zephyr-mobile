package com.zephyr.design.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/** Rounded 24dp card on surface2 with hairline border (prototype `.card`). */
@Composable
fun ZCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    padding: Dp = 0.dp,
    level: ZSurfaceLevel = ZSurfaceLevel.S2,
    shape: androidx.compose.ui.graphics.Shape = ZTheme.shapes.card,
    content: @Composable ColumnScope.() -> Unit,
) {
    ZSurface(modifier.fillMaxWidth(), shape = shape, level = level) {
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
                .padding(padding),
            content = content,
        )
    }
}
