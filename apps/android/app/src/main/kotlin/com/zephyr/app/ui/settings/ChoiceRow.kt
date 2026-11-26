package com.zephyr.app.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.zephyr.app.ui.home.BelowAnchor
import com.zephyr.app.ui.home.PopupToggle
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZSurfaceStyle
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme

/**
 * Review L-P2-10: a "value ›" settings row opens its options instead of silently cycling to the next one on
 * each tap. The row itself looks exactly as before; the choices show in a small raised popup under it.
 */
@Composable
internal fun <T> ChoiceRow(
    title: String,
    options: List<Pair<T, String>>,
    selected: T,
    onSelect: (T) -> Unit,
    subtitle: String? = null,
) {
    // Issue #1: the same retap-closes contract as Home's 规则 ⌄ panel.
    val toggle = remember { PopupToggle() }
    val open = toggle.open
    val c = ZTheme.colors
    Box {
        ZSettingsRow(
            title, subtitle = subtitle, value = options.firstOrNull { it.first == selected }?.second,
            chevron = true, onClick = { toggle.toggle() },
        )
        if (open) {
            // The popup window sits below the row, not over it with transparent padding, so tapping the row again is an
            // outside touch (→ dismiss) and PopupToggle keeps it closed.
            val density = LocalDensity.current
            val provider = remember(density) {
                with(density) { BelowAnchor(minTop = 48.dp.roundToPx(), alignEnd = true, endInset = 16.dp.roundToPx()) }
            }
            Popup(
                popupPositionProvider = provider,
                onDismissRequest = { toggle.dismiss() }, properties = PopupProperties(focusable = true),
            ) {
                ZSurface(Modifier.width(200.dp), style = ZSurfaceStyle.Raised, shape = ZTheme.shapes.surface) {
                    Column(Modifier.padding(vertical = 6.dp).selectableGroup()) {
                        options.forEach { (v, label) ->
                            Row(
                                Modifier.fillMaxWidth()
                                    .selectable(selected = v == selected, role = Role.RadioButton) { toggle.close(); if (v != selected) onSelect(v) }
                                    .padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                ZText(label, Modifier.weight(1f), style = ZTheme.type.body)
                                if (v == selected) ZIcon(ZIcons.Check, tint = c.accentText, size = 18.dp)
                            }
                        }
                    }
                }
            }
        }
    }
}
