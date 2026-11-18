package com.zephyr.app.ui.activity

import com.zephyr.app.ui.common.sceneName
import com.zephyr.app.R
import com.zephyr.app.ui.common.collectWhile
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiText
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.zephyr.design.theme.ZAnim
import androidx.compose.animation.core.animateFloat
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.LocalNow
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSegmented
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToggle
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ConnectionTrace
import com.zephyr.engine.TraceTarget
import kotlinx.coroutines.launch

/** Connection trace (prototype `trace`): 规则 → 场景 → 节点 → 出口, plus a one-off or permanent override. */
@Composable
fun BoxScope.TraceSheet(host: String?, onDismiss: () -> Unit) {
    ZSheet(host != null, onDismiss, "") { TraceBody(host) }
}

/** Trace content, shared by the stand-alone sheet and the in-place step inside "最近连接" (review H-P2-9). */
@Composable
internal fun androidx.compose.foundation.layout.ColumnScope.TraceBody(host: String?, onApplied: ((UiText, suspend () -> Unit) -> Unit)? = null) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    val now = LocalNow.current()
    val scenes by remember { engine.scenes() }.collectWhile(host != null, emptyList())
    var reload by remember { mutableStateOf(0) }
    val trace by produceState<ConnectionTrace?>(null, host, reload) { value = host?.let { runCatching { engine.connectionTrace(it) }.getOrNull() } }
    val scope = rememberCoroutineScope()
    var overrideError by remember(host) { mutableStateOf<String?>(null) }
    val res = LocalResources.current
    run {
        val t = trace ?: return
        Column(Modifier.padding(horizontal = 22.dp)) {
            // Review H-P2-10: prototype `.tr h2` is 300 32px, not the hero face.
            ZText(t.host, style = ZTheme.type.title.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Light, fontSize = 32.sp, lineHeight = 38.sp), maxLines = 1)
            ZText(listOf(ZFormat.ago(res, t.lastSeenAt, now), pluralStringResource(R.plurals.trace_connections, t.connections, t.connections), ZFormat.bytesText(t.totalBytes)).joinToString(" · "), style = ZTheme.type.callout, color = c.text3)
            Spacer(Modifier.height(24.dp))
            val sceneName = t.scene?.let { id -> scenes.firstOrNull { it.id == id }?.let { res.sceneName(it) } ?: id }
            // Review H-P2-10: 逐步出现（原型 256-258；iOS TraceView 0.08 s + i × 0.06 s）+ 竖线流光（原型 1006，iOS TraceRailFlow）。
            Box {
                Column {
                    Step(0, stringResource(R.string.trace_step_rule), t.rule.replace(",", ", "), t.ruleSource?.let { stringResource(R.string.trace_from, it) }, mono = true)
                    Step(1, stringResource(R.string.trace_step_scene), sceneName ?: stringResource(R.string.common_direct), t.sceneSource)
                    t.node?.let { Step(2, stringResource(R.string.trace_step_node), it.name, t.via?.let { v -> stringResource(R.string.trace_via, v) }) }
                    val stable = t.exitStableDays?.let { pluralStringResource(R.plurals.trace_exit_stable, it, it) }
                    Step(3, stringResource(R.string.trace_step_exit), t.exitIp ?: stringResource(R.string.common_local_network), listOfNotNull(t.exitRegion, stable).joinToString(" · ").ifEmpty { null }, mono = t.exitIp != null, last = true)
                }
                TraceRailFlow(Modifier.matchParentSize())
            }
        }
        Spacer(Modifier.height(16.dp))
        ZText(stringResource(R.string.trace_this_connection), Modifier.padding(horizontal = 26.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.text3)
        val others = scenes.filter { it.id != t.scene }.take(2)
        val opts = listOf(stringResource(R.string.trace_option_unchanged), stringResource(R.string.common_direct)) + others.map { res.sceneName(it) }
        val ov = t.override
        val sel = when (ov?.target) { null, TraceTarget.UNCHANGED -> 0; TraceTarget.DIRECT -> 1; TraceTarget.SCENE -> 2 + others.indexOfFirst { it.id == ov.sceneId }.coerceAtLeast(0) }
        val persistent = ov?.persistent ?: false
        fun apply(i: Int, keep: Boolean) = scope.launch {
            val (target, sid) = when (i) { 0 -> TraceTarget.UNCHANGED to null; 1 -> TraceTarget.DIRECT to null; else -> TraceTarget.SCENE to others[i - 2].id }
            val before = ov
            // Review H-P2-10: a failed override is shown instead of silently swallowed; audit U27: in our own words,
            // never the engine's message (contract §0.5), and a success can be undone.
            runCatching { engine.overrideHost(t.host, target, sid, keep) }
                .onSuccess {
                    overrideError = null
                    val msg = when (target) {
                        TraceTarget.UNCHANGED -> uiText(R.string.trace_override_cleared, t.host)
                        TraceTarget.DIRECT -> uiText(R.string.trace_override_direct, t.host)
                        TraceTarget.SCENE -> uiText(R.string.trace_override_scene, t.host, opts[i])
                    }
                    onApplied?.invoke(msg) {
                        engine.overrideHost(t.host, before?.target ?: TraceTarget.UNCHANGED, before?.sceneId, before?.persistent ?: false)
                        reload++
                    }
                }
                .onFailure { overrideError = res.getString(R.string.trace_override_error) }
            reload++
        }
        ZSegmented(opts, sel, { apply(it, persistent) }, Modifier.padding(horizontal = 16.dp))
        overrideError?.let { ZText(it, Modifier.padding(horizontal = 26.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.danger) }
        Spacer(Modifier.height(16.dp))
        ZListGroup {
            ZSettingsRow(stringResource(R.string.trace_always_apply), subtitle = stringResource(R.string.trace_always_apply_hint), checked = persistent, onCheckedChange = { v -> apply(sel, v) })
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun Step(index: Int, label: String, value: String, detail: String?, mono: Boolean = false, last: Boolean = false) {
    val c = ZTheme.colors
    val still = androidx.compose.ui.platform.LocalInspectionMode.current // previews/Paparazzi: final frame
    val shown = remember { androidx.compose.animation.core.Animatable(if (still) 1f else 0f) }
    androidx.compose.runtime.LaunchedEffect(Unit) {
        if (still) return@LaunchedEffect
        kotlinx.coroutines.delay(80L + index * 60L)
        shown.animateTo(1f, ZAnim.slow())
    }
    val dir = com.zephyr.app.ui.common.startToEndSign()
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).graphicsLayer {
        alpha = shown.value
        translationX = dir * (1f - shown.value) * -8.dp.toPx()
    }) {
        Box(Modifier.width(20.dp).fillMaxHeight()) {
            if (!last) Box(Modifier.align(Alignment.TopCenter).padding(top = 13.dp).width(1.dp).fillMaxHeight().background(c.hairlineStrong))
            Box(
                Modifier.padding(top = 2.dp).size(11.dp).align(Alignment.TopCenter)
                    .then(if (last) Modifier.background(c.connected, CircleShape) else Modifier.border(1.5.dp, c.text3, CircleShape)),
            )
        }
        Spacer(Modifier.width(16.dp))
        Column(Modifier.padding(bottom = 22.dp)) {
            ZText(label, style = ZTheme.type.footnote, color = c.text3)
            ZText(value, style = if (mono) ZTheme.type.mono.copy(fontSize = ZTheme.type.headline.fontSize) else ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
            detail?.let { ZText(it, style = ZTheme.type.callout, color = c.text3) }
        }
    }
}

/** A 40dp accent glint sliding down the step rail every 1.8 s (iOS TraceRailFlow parity). */
@Composable
private fun TraceRailFlow(modifier: Modifier) {
    if (androidx.compose.ui.platform.LocalInspectionMode.current) return
    val accent = ZTheme.colors.accent
    val t by androidx.compose.animation.core.rememberInfiniteTransition(label = "rail").animateFloat(
        0f, 1f,
        androidx.compose.animation.core.infiniteRepeatable<Float>(androidx.compose.animation.core.tween<Float>(1800, easing = androidx.compose.animation.core.FastOutSlowInEasing)),
        label = "railT",
    )
    val rtl = com.zephyr.app.ui.common.startToEndSign() < 0
    androidx.compose.foundation.Canvas(modifier.clearAndSetSemantics {}) {
        // The rail is the step dots' column at the start edge; Canvas x does not mirror by itself.
        val seg = 40.dp.toPx(); val x = if (rtl) size.width - 10.dp.toPx() else 10.dp.toPx(); val top = 13.dp.toPx(); val bottom = size.height - 48.dp.toPx()
        if (bottom <= top) return@Canvas
        val y = top - seg + (bottom - top + seg) * t
        val y0 = y.coerceAtLeast(top); val y1 = (y + seg).coerceAtMost(bottom)
        if (y1 <= y0) return@Canvas
        drawLine(
            androidx.compose.ui.graphics.Brush.verticalGradient(listOf(accent.copy(alpha = 0f), accent, accent.copy(alpha = 0f)), startY = y, endY = y + seg),
            androidx.compose.ui.geometry.Offset(x, y0), androidx.compose.ui.geometry.Offset(x, y1), strokeWidth = 1.5.dp.toPx(),
        )
    }
}
