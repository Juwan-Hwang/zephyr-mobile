package com.zephyr.app.ui.home

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.ui.layout.layout
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZButtonKind
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZRegionBadge
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.SceneSource

/** Scenes card (prototype home): scrub a row across regions, confirm inline, undo via toast. */
@Composable
fun SceneCard(
    scenes: List<Scene>,
    pending: PendingChange?,
    slots: Map<String, List<NodeSummary>>,
    onPick: (Scene, NodeSummary) -> Unit,
    onPrefetch: (Scene) -> Unit,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    onOpen: (Scene) -> Unit,
) {
    val hint = com.zephyr.app.ui.common.LocalScrubHint.current
    var hinted by remember(hint.seen) { mutableStateOf(hint.seen) }
    ZCard(Modifier.padding(horizontal = 16.dp)) {
        scenes.forEachIndexed { i, s ->
            if (i > 0) {
                ZDivider(inset = false)
                // Review H-P2-5: prototype `.coach` (122) floats on the divider under the AI row, masking it with the
                // card colour and nudging 6 dp left every 2.4 s; it takes no height, so the card never grows.
                val prev = scenes[i - 1]
                if (prev.kind == SceneKind.AI && !hinted && pending == null) ScrubCoach()
            }
            if (s.source != SceneSource.SUBSCRIPTION_GROUP) androidx.compose.runtime.LaunchedEffect(s.id, s.selected.id, s.source) { onPrefetch(s) }
            SceneRow(
                s, slots[s.id].orEmpty(), pendingNode = pending?.takeIf { it.scene.id == s.id }?.node,
                onScrubStart = { if (!hinted) { hinted = true; hint.markSeen() }; if (pending != null) onCancel() },
                onPick = { n -> onPick(s, n) }, onOpen = { onOpen(s) },
            )
            AnimatedVisibility(
                pending?.scene?.id == s.id,
                enter = expandVertically(ZAnim.slow()) + fadeIn(ZAnim.standard()),
                exit = shrinkVertically(ZAnim.standard()) + fadeOut(ZAnim.micro()),
            ) { pending?.let { ExitConfirm(it, onConfirm, onCancel) } }
        }
    }
}

@Composable
private fun SceneRow(
    s: Scene,
    slots: List<NodeSummary>,
    pendingNode: NodeSummary?,
    onScrubStart: () -> Unit,
    onPick: (NodeSummary) -> Unit,
    onOpen: () -> Unit,
) {
    val c = ZTheme.colors
    val hf = LocalHapticFeedback.current
    val swipeable = s.source != SceneSource.SUBSCRIPTION_GROUP && slots.size > 1
    val current = slots.indexOfFirst { it.id == s.selected.id }.coerceAtLeast(0)
    // Prototype scrub (978–988): every 42 dp crosses one slot, badge + node update live, tick + haptic per slot,
    // clamped at both ends; release on another slot opens the inline confirm. Pending confirm keeps its node shown.
    var scrubbing by remember { mutableStateOf(false) }
    var idx by remember(s.id, s.selected.id) { mutableStateOf(current) }
    var tick by remember { mutableStateOf(0) }
    // `.cc.tick`: a 120 ms pop on every slot crossed.
    val pop = remember { androidx.compose.animation.core.Animatable(1f) }
    androidx.compose.runtime.LaunchedEffect(tick) {
        if (tick > 0) { pop.snapTo(1.18f); pop.animateTo(1f, androidx.compose.animation.core.tween(120)) }
    }
    val shown = when {
        scrubbing -> slots.getOrNull(idx) ?: s.selected
        pendingNode != null -> pendingNode
        else -> s.selected
    }
    val stepPx = with(androidx.compose.ui.platform.LocalDensity.current) { 42.dp.toPx() }
    val latestSlots by androidx.compose.runtime.rememberUpdatedState(slots)
    val latestCurrent by androidx.compose.runtime.rememberUpdatedState(current)
    Box {
    Row(
        Modifier
            .fillMaxWidth()
            .then(
                if (swipeable) Modifier.pointerInput(s.id) {
                    var dx = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { dx = 0f; idx = latestCurrent; scrubbing = true; onScrubStart() },
                        onDragEnd = {
                            scrubbing = false
                            val target = latestSlots.getOrNull(idx)
                            if (target != null && target.id != s.selected.id) onPick(target) else idx = latestCurrent
                        },
                        onDragCancel = { scrubbing = false; idx = latestCurrent },
                    ) { _, d ->
                        dx += d
                        val i = (latestCurrent + kotlin.math.round(dx / stepPx).toInt()).coerceIn(0, latestSlots.lastIndex)
                        if (i != idx) { idx = i; tick++; hf.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick) }
                    }
                } else Modifier,
            )
            .semantics {
                if (swipeable) customActions = listOfNotNull(
                    slots.getOrNull(current + 1)?.let { n -> CustomAccessibilityAction("下一个地区：${n.name}") { onPick(n); true } },
                    slots.getOrNull(current - 1)?.let { n -> CustomAccessibilityAction("上一个地区：${n.name}") { onPick(n); true } },
                )
            }
            .zPressable(label = "${s.name} 场景详情", onClick = onOpen)
            .padding(horizontal = 18.dp, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Prototype 19 (xl): at large font sizes the row stacks — name, count, [badge] node, pin line — left-aligned,
        // two lines each, so the pin note ("Claude：US-Fixed-01") is never cut (review H-P1-4).
        val stacked = androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.3f
        val lines = if (stacked) 2 else 1
        val left: @Composable (Modifier) -> Unit = { m -> Column(m) {
            ZText(s.name, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight, fontSize = ZTheme.type.headline.fontSize * 1.1f), maxLines = lines)
            Spacer(Modifier.height(6.dp))
            val down = s.services.filter { !it.ok }
            ZText(
                when {
                    down.isNotEmpty() -> "${down.joinToString("、") { it.name }} 不可用"
                    s.source == SceneSource.SUBSCRIPTION_GROUP -> "订阅分组"
                    else -> "${s.available} 个可用"
                },
                style = ZTheme.type.callout, color = if (down.isNotEmpty()) c.danger else c.text3, maxLines = lines,
            )
        }
        }
        val right: @Composable (Modifier) -> Unit = { m -> Column(m, horizontalAlignment = if (stacked) Alignment.Start else Alignment.End) {
            AnimatedContent(
                targetState = shown,
                transitionSpec = { (slideInHorizontally(ZAnim.slow()) { it / 3 } + fadeIn(ZAnim.standard())) togetherWith fadeOut(ZAnim.micro()) },
                label = "node",
            ) { n ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ZRegionBadge(n.region, Modifier.graphicsLayer { scaleX = pop.value; scaleY = pop.value }, active = scrubbing)
                    Spacer(Modifier.width(10.dp))
                    ZText(n.name, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight), maxLines = lines)
                }
            }
            // Prototype 11 (zero): "Claude 不可用" left, "GPT、Gemini 正常" right, replacing the pin line.
            val up = s.services.filter { it.ok }
            val serviceLine = if (s.services.any { !it.ok } && up.isNotEmpty()) "${up.joinToString("、") { it.name }} 正常" else null
            val sub = serviceLine ?: s.exceptions.firstOrNull()?.let { "${it.app}：${it.node.name}" } ?: s.note
            if (sub != null) {
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (serviceLine == null && s.exceptions.isNotEmpty()) { ZIcon(ZIcons.Lock, tint = c.warning, size = 13.dp); Spacer(Modifier.width(6.dp)) }
                    ZText(sub, style = ZTheme.type.callout, color = c.text3, maxLines = lines)
                }
            }
        }
        }
        if (stacked) {
            Column(Modifier.fillMaxWidth()) { left(Modifier); Spacer(Modifier.height(10.dp)); right(Modifier) }
        } else {
            left(Modifier.weight(0.4f)); right(Modifier.weight(0.6f))
        }
    }
    // Track (prototype `.track`): one segment per slot, visible only while scrubbing.
    AnimatedVisibility(scrubbing, Modifier.align(Alignment.BottomCenter), enter = fadeIn(ZAnim.micro()), exit = fadeOut(ZAnim.standard())) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            slots.indices.forEach { k ->
                Box(Modifier.weight(1f).height(3.dp).background(if (k == idx) c.accent else c.hairlineStrong, ZTheme.shapes.pill))
            }
        }
    }
    }
}

@Composable
private fun ExitConfirm(p: PendingChange, onConfirm: () -> Unit, onCancel: () -> Unit) {
    // Review H-P2-6: prototype `.cf` (129-133): solid s3 + 1 dp --hl border, radius 16, padding 14, 14 sp title,
    // 6 dp amber dot, mono 12.5 IP line with a t4 arrow and the target IP in t1, 40 dp pill buttons 8 dp apart.
    val c = ZTheme.colors
    val apps = p.change.affectedApps
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp)
    Column(
        Modifier
            .padding(start = 16.dp, end = 16.dp, bottom = 14.dp)
            .fillMaxWidth()
            .background(c.surface3, shape)
            .border(1.dp, c.hairline, shape)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).background(c.warning, CircleShape))
            Spacer(Modifier.width(8.dp))
            ZText(
                if (apps.isNotEmpty()) "更改 ${apps.joinToString(" 和 ")} 的出口 IP？" else "更改 ${p.scene.name} 场景的出口 IP？",
                style = ZTheme.type.body.copy(fontSize = androidx.compose.ui.unit.TextUnit(14f, androidx.compose.ui.unit.TextUnitType.Sp)),
            )
        }
        Spacer(Modifier.height(6.dp))
        val mono = ZTheme.type.mono.copy(fontSize = androidx.compose.ui.unit.TextUnit(12.5f, androidx.compose.ui.unit.TextUnitType.Sp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ZText("${p.change.fromRegion} ${p.change.fromIp ?: "—"}", style = mono, color = c.text2, maxLines = 1)
            ZText("→", style = mono, color = c.text4)
            ZText("${p.change.toRegion} ${p.change.toIp ?: "—"}", style = mono, color = c.text1, maxLines = 1)
        }
        if (p.change.unchangedApps.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            ZText("${p.change.unchangedApps.joinToString("、")} 保持不变。", style = ZTheme.type.footnote.copy(fontSize = androidx.compose.ui.unit.TextUnit(12f, androidx.compose.ui.unit.TextUnitType.Sp)), color = c.text3)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CompactButton("更改", c.primaryButton, c.onPrimaryButton, onConfirm, Modifier.weight(1f))
            CompactButton("取消", c.hairline, c.text1, onCancel, Modifier.weight(1f))
        }
    }
}

/** Prototype `.btn` (135): 40 dp pill, 14/500; the 48 dp touch target extends invisibly around it. */
@Composable
private fun CompactButton(text: String, bg: androidx.compose.ui.graphics.Color, fg: androidx.compose.ui.graphics.Color, onClick: () -> Unit, modifier: Modifier) {
    Box(
        modifier.height(48.dp).zPressable(label = text, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.fillMaxWidth().height(40.dp).background(bg, ZTheme.shapes.pill), contentAlignment = Alignment.Center) {
            ZText(
                text,
                style = ZTheme.type.body.copy(
                    fontSize = androidx.compose.ui.unit.TextUnit(14f, androidx.compose.ui.unit.TextUnitType.Sp),
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                ),
                color = fg,
            )
        }
    }
}

@Composable
private fun ScrubCoach() {
    val nudge = androidx.compose.animation.core.rememberInfiniteTransition(label = "coach")
    val dx by nudge.animateFloat(
        0f, 0f,
        androidx.compose.animation.core.infiniteRepeatable(
            androidx.compose.animation.core.keyframes {
                durationMillis = 2400
                0f at 0; -6f at 720; 0f at 2400
            },
        ),
        label = "nudge",
    )
    ZText(
        "左右滑动以切换地区",
        Modifier
            .fillMaxWidth()
            .wrapContentWidth(Alignment.CenterHorizontally)
            .layout { m, c ->
                val p = m.measure(c.copy(minHeight = 0, maxHeight = androidx.compose.ui.unit.Constraints.Infinity))
                layout(c.maxWidth, 0) { p.place((c.maxWidth - p.width) / 2, -p.height / 2) }
            }
            .graphicsLayer { translationX = dx * density }
            .background(ZTheme.colors.surface2)
            .padding(horizontal = 8.dp),
        style = ZTheme.type.footnote.copy(fontSize = androidx.compose.ui.unit.TextUnit(11f, androidx.compose.ui.unit.TextUnitType.Sp)),
        color = ZTheme.colors.accent,
    )
}
