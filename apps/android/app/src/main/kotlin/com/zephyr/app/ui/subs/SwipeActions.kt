package com.zephyr.app.ui.subs

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** [keepOpen]: the row stays open after the tap (a first "删除" tap that arms "确认删除" in place). */
internal data class SwipeAction(val label: String, val color: Color, val keepOpen: Boolean = false, val onClick: () -> Unit)

/**
 * Review L-P2-9 (spec §4 “左滑更新/删除”): swipe a row toward the start edge (left in LTR, right in RTL) to reveal
 * its actions, which sit at the end edge; it snaps open past half the actions' width, closes on the opposite swipe
 * or after an action. TalkBack gets the same actions as custom actions.
 * [resetKey] closes the row when it changes (e.g. after the list updates); [onClosed] runs whenever it closes
 * (so an armed "确认删除" is disarmed when the row is swiped shut).
 */
@Composable
internal fun SwipeActionsRow(actions: List<SwipeAction>, resetKey: Any? = null, onClosed: () -> Unit = {}, content: @Composable () -> Unit) {
    val actionWidth = 76.dp
    val maxPx = with(LocalDensity.current) { (actionWidth * actions.size).toPx() }
    val offset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    // offset {} already mirrors x in RTL; the raw finger delta does not, so flip it to keep "drag follows finger".
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val closed by androidx.compose.runtime.rememberUpdatedState(onClosed)
    LaunchedEffect(resetKey) { offset.snapTo(0f) }
    LaunchedEffect(Unit) { androidx.compose.runtime.snapshotFlow { offset.value == 0f && !offset.isRunning }.collect { if (it) closed() } }
    fun close() = scope.launch { offset.animateTo(0f) }
    Box(Modifier.semantics { customActions = actions.map { a -> CustomAccessibilityAction(a.label) { a.onClick(); true } } }) {
        Row(Modifier.matchParentSize(), horizontalArrangement = androidx.compose.foundation.layout.Arrangement.End) {
            if (offset.value < 0f) actions.forEach { a ->
                Box(
                    Modifier.width(actionWidth).fillMaxHeight().background(a.color)
                        .clickable(role = Role.Button) { if (!a.keepOpen) close(); a.onClick() },
                    contentAlignment = Alignment.Center,
                ) { ZText(a.label, style = ZTheme.type.callout, color = Color.White) }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(offset.value.roundToInt(), 0) }
                .background(ZTheme.colors.surface2)
                .draggable(
                    rememberDraggableState { d -> scope.launch { offset.snapTo((offset.value + d).coerceIn(-maxPx, 0f)) } },
                    Orientation.Horizontal,
                    reverseDirection = rtl,
                    onDragStopped = { v -> offset.animateTo(if (offset.value < -maxPx / 2 || v < -800f) -maxPx else 0f) },
                ),
        ) { content() }
    }
}
