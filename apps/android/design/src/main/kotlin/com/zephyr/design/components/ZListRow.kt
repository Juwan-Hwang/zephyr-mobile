package com.zephyr.design.components

import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/** Grouped list container (iOS inset-grouped look, self-drawn on Android — spec §4). */
@Composable
fun ZListGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    ZSurface(modifier.fillMaxWidth().padding(horizontal = 16.dp), shape = ZTheme.shapes.card) {
        Column(Modifier.fillMaxWidth(), content = content)
    }
}

/** Hairline divider inset from the leading edge. */
@Composable
fun ZDivider(modifier: Modifier = Modifier, inset: Boolean = true) {
    Box(modifier.fillMaxWidth().padding(start = if (inset) 20.dp else 0.dp).height(1.dp).background(ZTheme.colors.hairline))
}

/** Settings row: title, optional subtitle, trailing value / chevron / custom control. */
@Composable
fun ZSettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    value: String? = null,
    chevron: Boolean = false,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    checked: Boolean? = null,
    onCheckedChange: ((Boolean) -> Unit)? = null,
) {
    val c = ZTheme.colors
    val hf = androidx.compose.ui.platform.LocalHapticFeedback.current
    // Review D-P1-3: a switch row toggles from anywhere on the row (≥ 56 dp target) and reads as one
    // "title, switch, on/off" node; the drawn switch itself is hidden from accessibility.
    val toggle = if (checked != null && onCheckedChange != null) Modifier.toggleable(checked, role = Role.Switch) { v ->
        hf.performHapticFeedback(if (v) androidx.compose.ui.hapticfeedback.HapticFeedbackType.ToggleOn else androidx.compose.ui.hapticfeedback.HapticFeedbackType.ToggleOff)
        onCheckedChange(v)
    } else null
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp)
            .then(toggle ?: if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            ZText(title, style = ZTheme.type.body, color = c.text1)
            if (subtitle != null) ZText(subtitle, style = ZTheme.type.footnote, color = c.text3)
        }
        if (value != null) {
            Spacer(Modifier.width(12.dp))
            ZText(value, style = ZTheme.type.body, color = c.text3, maxLines = 1)
        }
        if (trailing != null) { Spacer(Modifier.width(12.dp)); trailing() }
        if (toggle != null) {
            Spacer(Modifier.width(12.dp))
            ZToggle(checked!!, { onCheckedChange!!(it) }, Modifier.clearAndSetSemantics {})
        }
        if (chevron) { Spacer(Modifier.width(6.dp)); ZIcon(ZIcons.ChevronRight, tint = c.text4, size = 16.dp) }
    }
}
