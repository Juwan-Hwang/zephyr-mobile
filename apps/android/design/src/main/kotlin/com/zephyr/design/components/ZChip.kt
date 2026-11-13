package com.zephyr.design.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
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

/** Filter chip ("US 312 万"). Selected = inverted pill. */
@Composable
fun ZChip(label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, detail: String? = null) {
    val c = ZTheme.colors
    val bg by animateColorAsState(if (selected) c.text1 else c.bg.copy(alpha = 0f), ZAnim.standard(), label = "chip")
    val fg = if (selected) c.bg else c.text1
    Row(
        modifier
            .height(40.dp)
            .clip(ZTheme.shapes.pill)
            .background(bg)
            .border(1.dp, if (selected) c.text1 else c.hairlineStrong, ZTheme.shapes.pill)
            .semantics { this.selected = selected }
            .zPressable(role = Role.Tab, haptic = !selected, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ZText(label, style = ZTheme.type.callout, color = fg, maxLines = 1)
        if (detail != null) {
            Spacer(Modifier.width(6.dp))
            ZText(detail, style = ZTheme.type.monoSmall, color = if (selected) c.bg.copy(alpha = 0.6f) else c.text3, maxLines = 1)
        }
    }
}
