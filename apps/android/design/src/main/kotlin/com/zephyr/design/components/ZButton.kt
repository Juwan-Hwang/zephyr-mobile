package com.zephyr.design.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

enum class ZButtonKind { Primary, Secondary, Ghost, Danger, Accent }

/** Pill button. Primary = light pill on dark (prototype "应用"/"分享"), Secondary = surface pill. */
@Composable
fun ZButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ZButtonKind = ZButtonKind.Primary,
    enabled: Boolean = true,
) {
    val c = ZTheme.colors
    val (bg, fg) = when (kind) {
        ZButtonKind.Primary -> c.primaryButton to c.onPrimaryButton
        ZButtonKind.Secondary -> c.surface3 to c.text1
        ZButtonKind.Ghost -> c.bg.copy(alpha = 0f) to c.accent
        ZButtonKind.Danger -> c.danger.copy(alpha = 0.14f) to c.danger
        ZButtonKind.Accent -> c.accent to c.onAccent
    }
    val shape = ZTheme.shapes.pill
    Box(
        modifier
            .defaultMinSize(minHeight = 52.dp)
            .alpha(if (enabled) 1f else 0.4f)
            .clip(shape)
            .background(bg, shape)
            .then(if (kind == ZButtonKind.Secondary) Modifier.border(1.dp, c.hairline, shape) else Modifier)
            .zPressable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        ZText(text, style = ZTheme.type.button, color = fg, maxLines = 1)
    }
}
