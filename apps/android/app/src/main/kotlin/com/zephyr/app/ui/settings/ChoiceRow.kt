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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
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
    var open by remember { mutableStateOf(false) }
    val c = ZTheme.colors
    Box {
        ZSettingsRow(
            title, subtitle = subtitle, value = options.firstOrNull { it.first == selected }?.second,
            chevron = true, onClick = { open = true },
        )
        if (open) {
            Popup(
                alignment = Alignment.TopEnd, offset = IntOffset(0, 0),
                onDismissRequest = { open = false }, properties = PopupProperties(focusable = true),
            ) {
                ZSurface(Modifier.padding(top = 48.dp, end = 16.dp).width(200.dp), style = ZSurfaceStyle.Raised, shape = ZTheme.shapes.surface) {
                    Column(Modifier.padding(vertical = 6.dp).selectableGroup()) {
                        options.forEach { (v, label) ->
                            Row(
                                Modifier.fillMaxWidth()
                                    .selectable(selected = v == selected, role = Role.RadioButton) { open = false; if (v != selected) onSelect(v) }
                                    .padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                ZText(label, Modifier.weight(1f), style = ZTheme.type.body)
                                if (v == selected) ZIcon(ZIcons.Check, tint = c.accent, size = 18.dp)
                            }
                        }
                    }
                }
            }
        }
    }
}
