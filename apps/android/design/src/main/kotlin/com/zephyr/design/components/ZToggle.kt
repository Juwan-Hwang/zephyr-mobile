package com.zephyr.design.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme

enum class ZToggleSize(val width: Dp, val height: Dp) { Regular(51.dp, 31.dp), Hero(66.dp, 40.dp) }

/** Self-drawn switch with identical size and motion on both platforms (spec §5). */
@Composable
fun ZToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    size: ZToggleSize = ZToggleSize.Regular,
    onColor: Color = ZTheme.colors.connected,
    enabled: Boolean = true,
    contentDescription: String? = null,
) {
    val c = ZTheme.colors
    val track by animateColorAsState(if (checked) onColor else c.surface4, ZAnim.standard(), label = "track")
    val inset = 2.dp
    val knob = size.height - inset * 2
    val x by animateDpAsState(if (checked) size.width - knob - inset * 2 else 0.dp, ZAnim.bouncy(), label = "knob")
    val hf = LocalHapticFeedback.current
    Box(
        modifier
            .size(size.width, size.height)
            .clip(CircleShape)
            .background(track)
            .toggleable(
                value = checked, enabled = enabled, role = Role.Switch,
                interactionSource = remember { MutableInteractionSource() }, indication = null,
            ) { hf.performHapticFeedback(HapticFeedbackType.ToggleOn); onCheckedChange(it) }
            .padding(inset),
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            Modifier
                .offset(x = x)
                .size(knob)
                .shadow(2.dp, CircleShape)
                .background(Color.White, CircleShape),
        )
    }
}
