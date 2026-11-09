package com.zephyr.design.components

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.heightIn
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.dismiss
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Self-drawn bottom sheet (same radius/glass as iOS sheet detents, spec §5).
 * Drag down or predictive-back to dismiss; scrim tap dismisses. Hosted inside the screen's Box.
 */
@Composable
fun BoxScope.ZSheet(
    visible: Boolean,
    onDismiss: () -> Unit,
    title: String,
    modifier: Modifier = Modifier,
    trailing: String? = "完成",
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = ZTheme.colors
    AnimatedVisibility(visible, enter = fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.standard())) {
        Box(
            Modifier
                .fillMaxSize()
                .background(c.scrim)
                .clickable(remember { MutableInteractionSource() }, null, onClickLabel = "关闭", onClick = onDismiss),
        )
    }
    AnimatedVisibility(
        visible,
        modifier = Modifier.align(Alignment.BottomCenter),
        enter = slideInVertically(ZAnim.slow()) { it },
        exit = slideOutVertically(ZAnim.standard()) { it },
    ) {
        val drag = remember { Animatable(0f) }
        val scope = rememberCoroutineScope()
        PredictiveBackHandler(enabled = visible) { progress ->
            try {
                progress.collect { e -> drag.snapTo(e.progress * 160f) }
                onDismiss()
            } catch (_: CancellationException) {
                drag.animateTo(0f, ZAnim.standard())
            }
        }
        // Review D-P1-1: like the prototype (.sheet{top:58px}, .sh-body{overflow-y:auto}) the sheet stops 58 dp below
        // the status bar and its body scrolls; handle and title stay put.
        val density = androidx.compose.ui.platform.LocalDensity.current
        val screenH = with(density) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.height.toDp() }
        val topInset = with(density) { WindowInsets.statusBars.getTop(this).toDp() }
        Column(
            modifier
                .fillMaxWidth()
                .then(if (screenH > 0.dp) Modifier.heightIn(max = screenH - topInset - 58.dp) else Modifier)
                .offset { IntOffset(0, drag.value.coerceAtLeast(0f).roundToInt()) }
                .graphicsLayer { val p = (drag.value / 1600f).coerceIn(0f, 0.04f); scaleX = 1 - p; scaleY = 1 - p }
                .clip(ZTheme.shapes.sheet)
                .background(c.surface1)
                .semantics { paneTitle = title; dismiss { onDismiss(); true } }
                .draggable(
                    rememberDraggableState { d -> scope.launch { drag.snapTo((drag.value + d).coerceAtLeast(0f)) } },
                    Orientation.Vertical,
                    onDragStopped = { v -> if (drag.value > 140f || v > 1800f) onDismiss() else drag.animateTo(0f, ZAnim.bouncy()) },
                )
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
        ) {
            Box(Modifier.fillMaxWidth().padding(top = 10.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(width = 36.dp, height = 5.dp).clip(ZTheme.shapes.pill).background(c.text4))
            }
            Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 10.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                ZText(title, style = ZTheme.type.headline)
                Spacer(Modifier.weight(1f))
                if (trailing != null) {
                    ZText(trailing, Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).zPressable(onClick = onDismiss).padding(12.dp), style = ZTheme.type.body, color = c.text2)
                }
            }
            Spacer(Modifier.height(4.dp))
            Column(Modifier.weight(1f, fill = false).verticalScroll(androidx.compose.foundation.rememberScrollState()), content = content)
        }
    }
}
