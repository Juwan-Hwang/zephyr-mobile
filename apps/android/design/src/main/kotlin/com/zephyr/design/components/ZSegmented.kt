package com.zephyr.design.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme

/** Segmented control (规则 / 全局 / 直连) with a sliding thumb. */
@Composable
fun ZSegmented(
    options: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = ZTheme.colors
    val shape = ZTheme.shapes.control
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(36.dp)
            .clip(shape)
            .background(c.surface3)
            .padding(2.dp),
    ) {
        val segW = maxWidth / options.size
        val x by animateDpAsState(segW * selected, ZAnim.bouncy(), label = "seg")
        Box(Modifier.offset(x = x).width(segW).fillMaxHeight().clip(ZTheme.shapes.control).background(c.surface4))
        Row(Modifier.fillMaxWidth()) {
            options.forEachIndexed { i, label ->
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .semantics { this.selected = i == selected }
                        .zPressable(role = Role.Tab, haptic = i != selected) { onSelect(i) },
                    contentAlignment = Alignment.Center,
                ) {
                    ZText(label, style = ZTheme.type.footnote, color = if (i == selected) c.text1 else c.text2, maxLines = 1)
                }
            }
        }
    }
}
