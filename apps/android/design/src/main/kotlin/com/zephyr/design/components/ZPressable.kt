package com.zephyr.design.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.tokens.ZMotion

/**
 * Press-to-shrink (0.97, tokens `motion.press-scale`). [haptic] = a light tick; review D-P1-2: only pass it
 * when the press changes a selection (prototype vibrates only while scrubbing), never for plain buttons.
 */
fun Modifier.zPressable(
    enabled: Boolean = true,
    haptic: Boolean = false,
    role: Role = Role.Button,
    label: String? = null,
    longClickLabel: String? = null,
    onLongClick: (() -> Unit)? = null,
    onClick: () -> Unit,
): Modifier = composed {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) ZMotion.pressScale else 1f, ZAnim.micro(), label = "press")
    val hf = LocalHapticFeedback.current
    this
        .graphicsLayer { scaleX = scale; scaleY = scale }
        .then(
            if (onLongClick == null) Modifier.clickable(source, indication = null, enabled = enabled, onClickLabel = label, role = role) {
                if (haptic) hf.performHapticFeedback(HapticFeedbackType.SegmentTick)
                onClick()
            }
            else @OptIn(ExperimentalFoundationApi::class) Modifier.combinedClickable(
                source, indication = null, enabled = enabled, onClickLabel = label, role = role,
                onLongClickLabel = longClickLabel,
                onLongClick = { hf.performHapticFeedback(HapticFeedbackType.LongPress); onLongClick() },
            ) {
                if (haptic) hf.performHapticFeedback(HapticFeedbackType.SegmentTick)
                onClick()
            },
        )
}
