package com.zephyr.app.ui.home

import com.zephyr.app.ui.common.displayName
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
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
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.ui.common.joinAnd
import com.zephyr.app.ui.common.joinList
import com.zephyr.design.components.ZSurfaceLevel
import androidx.compose.foundation.shape.RoundedCornerShape
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
    retesting: Set<String>,
    scan: com.zephyr.engine.ScanProgress?,
    onPick: (Scene, NodeSummary) -> Unit,
    onPrefetch: (Scene) -> Unit,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    onOpen: (Scene) -> Unit,
    /** J-1 mini funnel per row (contract v0.7 §19.a); a missing entry keeps the "n 个可用" text. */
    funnels: Map<String, com.zephyr.engine.NodeFunnel> = emptyMap(),
    onFunnel: (Scene) -> Unit = {},
) {
    val hint = com.zephyr.app.ui.common.LocalScrubHint.current
    var hinted by remember(hint.seen) { mutableStateOf(hint.seen) }
    ZCard(Modifier.padding(horizontal = 16.dp), level = ZSurfaceLevel.S1, shape = RoundedCornerShape(22.dp)) {
        scenes.forEachIndexed { i, s ->
            if (i > 0) {
                ZDivider(inset = false)
                // Review H-P2-5: prototype `.coach` (122) floats on the divider under the AI row, masking it with the
                // card colour and nudging 6 dp left every 2.4 s; it takes no height, so the card never grows.
                val prev = scenes[i - 1]
                if (prev.kind == SceneKind.AI && !hinted && pending == null) ScrubCoach()
            }
            if (s.source != SceneSource.SUBSCRIPTION_GROUP) androidx.compose.runtime.LaunchedEffect(s.id, s.selected.id, s.source) { onPrefetch(s) }
            // Re-count on re-test, exit change (region), node filter change (§19.a range).
            if (s.source != SceneSource.SUBSCRIPTION_GROUP) androidx.compose.runtime.LaunchedEffect(s.id, s.selected.region, s.testedAt, s.nodeFilter) { onFunnel(s) }
            SceneRow(
                s, slots[s.id].orEmpty(), pendingNode = pending?.takeIf { it.scene.id == s.id }?.node,
                probing = if (s.id in retesting) (scan?.fraction ?: 0f) else null,
                funnel = funnels[s.id]?.takeIf { it.poolSize > 0 },
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
    /** Prototype 10 (scan): non-null while this scene is re-tested, the pool scan's fraction done. */
    probing: Float?,
    /** Spec §9.3: drawn instead of "n 个可用" only when counted (poolSize > 0); never a made-up ratio. */
    funnel: com.zephyr.engine.NodeFunnel?,
    onScrubStart: () -> Unit,
    onPick: (NodeSummary) -> Unit,
    onOpen: () -> Unit,
) {
    val c = ZTheme.colors
    val res = LocalResources.current
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
    // RTL: dragging toward the end edge (left) still means "next", like a mirrored slider.
    val dir = com.zephyr.app.ui.common.startToEndSign()
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
                        dx += d * dir
                        val i = (latestCurrent + kotlin.math.round(dx / stepPx).toInt()).coerceIn(0, latestSlots.lastIndex)
                        if (i != idx) { idx = i; tick++; hf.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick) }
                    }
                } else Modifier,
            )
            .semantics {
                if (swipeable) customActions = listOfNotNull(
                    slots.getOrNull(current + 1)?.let { n -> CustomAccessibilityAction(res.getString(R.string.home_scene_next_region, n.name)) { onPick(n); true } },
                    slots.getOrNull(current - 1)?.let { n -> CustomAccessibilityAction(res.getString(R.string.home_scene_prev_region, n.name)) { onPick(n); true } },
                )
            }
            .zPressable(row = true, label = stringResource(R.string.home_scene_details_a11y, s.displayName()), onClick = onOpen)
            .padding(horizontal = 16.dp, vertical = 15.dp), // review H-P2-4: `.row` 15/16
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Prototype 19 (xl): at large font sizes the row stacks — name, count, [badge] node, pin line — left-aligned,
        // two lines each, so the pin note ("Claude：US-Fixed-01") is never cut (review H-P1-4).
        val stacked = androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.3f
        val lines = if (stacked) 2 else 1
        val left: @Composable (Modifier) -> Unit = { m -> Column(m) {
            // Review H-P2-4: prototype `.row .n` 17 / −0.01em, `.m` 13 with 3 px gap, `.ex` 15, `.pin` 12 with 5 px gap.
            ZText(s.displayName(), style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight, fontSize = 17.sp, letterSpacing = (-0.01).em), maxLines = lines)
            Spacer(Modifier.height(3.dp))
            val down = s.services.filter { !it.ok }
            if (probing != null) {
                // Prototype 10: "4 个可用" over a 96 dp accent bar that fills as the pool scan advances.
                val testing = stringResource(R.string.home_scene_testing)
                ZText(if (s.available > 0) pluralStringResource(R.plurals.common_available_count, s.available, s.available) + " · " + testing else testing, style = ZTheme.type.callout.copy(fontSize = 13.sp), color = c.text3, maxLines = lines)
                Spacer(Modifier.height(6.dp))
                val shown by androidx.compose.animation.core.animateFloatAsState(probing, label = "scan")
                com.zephyr.design.components.ZProgressBar(shown, Modifier.width(96.dp), color = c.accent)
            } else if (down.isEmpty() && s.source != SceneSource.SUBSCRIPTION_GROUP && funnel != null) {
                Spacer(Modifier.height(4.dp))
                MiniFunnel(funnel)
            } else ZText(
                when {
                    down.isNotEmpty() -> stringResource(R.string.home_scene_services_down, joinList(down.map { it.name }))
                    s.source == SceneSource.SUBSCRIPTION_GROUP -> stringResource(R.string.common_source_group)
                    else -> pluralStringResource(R.plurals.common_available_count, s.available, s.available)
                },
                style = ZTheme.type.callout.copy(fontSize = 13.sp), color = if (down.isNotEmpty()) c.dangerText else c.text3, maxLines = lines,
            )
        }
        }
        val right: @Composable (Modifier) -> Unit = { m -> Column(m, horizontalAlignment = if (stacked) Alignment.Start else Alignment.End) {
            AnimatedContent(
                targetState = shown,
                transitionSpec = { (slideInHorizontally(ZAnim.slow()) { dir * it / 3 } + fadeIn(ZAnim.standard())) togetherWith fadeOut(ZAnim.micro()) },
                label = "node",
            ) { n ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ZRegionBadge(n.region, Modifier.graphicsLayer { scaleX = pop.value; scaleY = pop.value }, active = scrubbing)
                    Spacer(Modifier.width(10.dp))
                    ZText(n.name, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight, fontSize = 15.sp), maxLines = lines)
                }
            }
            // Prototype 11 (zero): "Claude 不可用" left, "GPT、Gemini 正常" right, replacing the pin line.
            val up = s.services.filter { it.ok }
            val serviceLine = if (s.services.any { !it.ok } && up.isNotEmpty()) stringResource(R.string.home_scene_services_ok, joinList(up.map { it.name })) else null
            val sub = serviceLine ?: s.exceptions.firstOrNull()?.let { stringResource(R.string.home_pin_line, it.app, it.node.name) } ?: s.note
            if (sub != null) {
                Spacer(Modifier.height(5.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (serviceLine == null && s.exceptions.isNotEmpty()) { ZIcon(ZIcons.Lock, Modifier.alpha(0.85f), tint = c.warning, size = 12.dp); Spacer(Modifier.width(6.dp)) }
                    ZText(sub, style = ZTheme.type.callout.copy(fontSize = 12.sp), color = c.text3, maxLines = lines)
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
                if (apps.isNotEmpty()) stringResource(R.string.home_confirm_apps, LocalResources.current.joinAnd(apps)) else stringResource(R.string.home_confirm_scene, p.scene.displayName()),
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
            ZText(stringResource(R.string.home_confirm_unchanged, joinList(p.change.unchangedApps)), style = ZTheme.type.footnote.copy(fontSize = androidx.compose.ui.unit.TextUnit(12f, androidx.compose.ui.unit.TextUnitType.Sp)), color = c.text3)
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CompactButton(stringResource(R.string.common_change), c.accentFill, c.onAccentFill, onConfirm, Modifier.weight(1f))
            CompactButton(stringResource(R.string.common_cancel), c.hairline, c.text1, onCancel, Modifier.weight(1f))
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
    val dir = com.zephyr.app.ui.common.startToEndSign()
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
        stringResource(R.string.home_scrub_hint),
        Modifier
            .fillMaxWidth()
            .wrapContentWidth(Alignment.CenterHorizontally)
            .layout { m, c ->
                val p = m.measure(c.copy(minHeight = 0, maxHeight = androidx.compose.ui.unit.Constraints.Infinity))
                layout(c.maxWidth, 0) { p.place((c.maxWidth - p.width) / 2, -p.height / 2) }
            }
            .graphicsLayer { translationX = dir * dx * density }
            .background(ZTheme.colors.surface2)
            .padding(horizontal = 8.dp),
        style = ZTheme.type.footnote.copy(fontSize = androidx.compose.ui.unit.TextUnit(11f, androidx.compose.ui.unit.TextUnitType.Sp)),
        color = ZTheme.colors.accentText,
    )
}
