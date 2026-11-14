package com.zephyr.design.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

enum class ZSurfaceStyle { Solid, Glass, Raised }

/** Review D-P2-1: page-level cards (home `.rows`/`.gb`, library `.grp`) sit on s1; sheet lists on s2. */
enum class ZSurfaceLevel { S1, S2 }

/**
 * Layered surface: hierarchy from tone + 1px hairline, never heavy shadows (spec §1).
 * Glass uses the prototype's 82% tint; real blur is applied by the caller where content scrolls beneath.
 */
@Composable
fun ZSurface(
    modifier: Modifier = Modifier,
    style: ZSurfaceStyle = ZSurfaceStyle.Solid,
    shape: Shape = ZTheme.shapes.card,
    bordered: Boolean = true,
    level: ZSurfaceLevel = ZSurfaceLevel.S2,
    content: @Composable () -> Unit,
) {
    val c = ZTheme.colors
    val bg = when (style) {
        ZSurfaceStyle.Solid -> if (level == ZSurfaceLevel.S1) c.surface1 else c.surface2
        ZSurfaceStyle.Glass -> c.glass
        ZSurfaceStyle.Raised -> c.surface3
    }
    Box(
        modifier
            .clip(shape)
            .background(bg, shape)
            .then(if (bordered) Modifier.border(1.dp, c.hairline, shape) else Modifier),
    ) { content() }
}
