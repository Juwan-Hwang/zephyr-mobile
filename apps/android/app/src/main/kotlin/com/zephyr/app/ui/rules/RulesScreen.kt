package com.zephyr.app.ui.rules

import com.zephyr.app.ui.common.displayName
import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.zephyr.app.R
import com.zephyr.app.ui.activity.TraceSheet
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.border
import androidx.compose.ui.unit.sp
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.app.ui.common.toPluralCount
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZRegionBadge
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.LayerKind
import com.zephyr.engine.RuleStats
import com.zephyr.engine.RuleTrace
import kotlinx.coroutines.delay

/** Rules (prototype `rules`): 7 compiled layers in match order + live domain/IP trace. */
@Composable
fun RulesScreen(initial: String, back: BackTo = BackTo.LIBRARY, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    var q by remember { mutableStateOf(initial) }
    val stats by produceState<RuleStats?>(null) { value = engine.ruleStats() }
    val trace by produceState<RuleTrace?>(null, q) {
        if (q.isBlank()) { value = null; return@produceState }
        if (q != initial) delay(60) // debounce typing, not the deep-linked first query
        value = runCatching { engine.testRule(q) }.getOrNull()
    }
    // Review L-P2-8: 原型右上“+”。添加覆写走与轨迹页同一张 TraceSheet（目标/场景/保留），以搜索框里的域名为对象。
    var overrideHost by remember { mutableStateOf<String?>(null) }
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    androidx.compose.foundation.layout.Box(Modifier.fillMaxSize()) {
    PageScaffold(back = back, title = stringResource(R.string.common_rules), onBack = onBack, trailing = {
        com.zephyr.design.components.ZIconButton(com.zephyr.design.components.ZIcons.Plus, stringResource(R.string.rules_add_override_a11y), {
            val h = q.trim()
            if (h.isEmpty()) runCatching { focus.requestFocus() } else overrideHost = h
        }, tint = c.accentText)
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
                ZText(ZFormat.grouped(stats?.total ?: 0), style = ZTheme.type.hero.copy(fontSize = ZTheme.type.hero.fontSize * 0.86f))
                Spacer(Modifier.width(8.dp))
                ZText(pluralStringResource(R.plurals.rules_total_unit, (stats?.total ?: 0L).toPluralCount()), Modifier.padding(bottom = 10.dp), style = ZTheme.type.body, color = c.text3)
            }
            val layerCount = stats?.layers?.size ?: 7
            ZText(pluralStringResource(R.plurals.rules_summary, layerCount, layerCount, ZFormat.bytesText(stats?.diskBytes ?: 0)), Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
            Spacer(Modifier.height(18.dp))
            ZSearchField(q, { q = it }, stringResource(R.string.rules_test_placeholder), Modifier.padding(horizontal = 16.dp).focusRequester(focus))
            Spacer(Modifier.height(12.dp))
            ZCard(Modifier.padding(horizontal = 16.dp), padding = 18.dp) {
                AnimatedContent(trace, transitionSpec = { fadeIn(ZAnim.standard()) togetherWith fadeOut(ZAnim.micro()) }, label = "trace") { t ->
                    if (t == null) ZText(stringResource(R.string.rules_test_hint), style = ZTheme.type.footnote, color = c.text3)
                    else Chain(t, stats)
                }
            }
            Spacer(Modifier.height(20.dp))
            ZSectionHeader(stringResource(R.string.rules_match_order), trailing = stringResource(R.string.rules_top_to_bottom))
            ZCard(Modifier.padding(horizontal = 16.dp)) {
                val hit = trace
                stats?.layers?.forEachIndexed { i, l ->
                    if (i > 0) ZDivider(inset = false)
                    LayerRow(i + 1, l.name, l.note, stringResource(kindLabel(l.kind)), ZFormat.grouped(l.count), hit != null && hit.layerIndex == l.index, accent = l.kind == LayerKind.OVERRIDE)
                }
                ZDivider(inset = false)
                LayerRow((stats?.layers?.size ?: 7) + 1, stringResource(R.string.rules_other_traffic), "MATCH", null, stringResource(R.string.rules_kind_other), trace != null && trace!!.layerIndex == null, false)
            }
            ZText(
                stringResource(R.string.rules_note),
                Modifier.padding(horizontal = 22.dp, vertical = 14.dp), style = ZTheme.type.footnote, color = c.text3,
            )
            Spacer(Modifier.height(40.dp))
        }
    }
    TraceSheet(overrideHost) { overrideHost = null }
    }
}

@StringRes
private fun kindLabel(k: LayerKind): Int = when (k) {
    LayerKind.OVERRIDE -> R.string.rules_kind_override
    LayerKind.SUBSCRIPTION -> R.string.rules_kind_subscription
    LayerKind.DOMAIN -> R.string.rules_kind_domain
    LayerKind.IP -> R.string.rules_kind_ip
}

@Composable
private fun LayerRow(ix: Int, name: String, note: String, kind: String?, count: String, hit: Boolean, accent: Boolean) {
    val c = ZTheme.colors
    val bg by animateColorAsState(if (hit) c.accent.copy(alpha = 0.09f) else c.bg.copy(alpha = 0f), ZAnim.standard(), label = "hit")
    Row(Modifier.fillMaxWidth().background(bg).padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        ZText("$ix", Modifier.width(24.dp), style = ZTheme.type.mono, color = if (hit) c.accentText else c.text3)
        Column(Modifier.weight(1f)) {
            ZText(name, style = ZTheme.type.body, maxLines = 1)
            ZText(note, style = ZTheme.type.caption, color = c.text3, maxLines = 1)
        }
        if (kind != null) {
            // Review L-P2-8: prototype layer tag is a 1px outline, 10px mono.
            ZText(kind, Modifier.border(1.dp, if (accent) c.accent else c.hairlineStrong, ZTheme.shapes.control).padding(horizontal = 7.dp, vertical = 2.dp), style = ZTheme.type.monoSmall.copy(fontSize = 10.sp), color = if (accent) c.accentText else c.text2)
            Spacer(Modifier.width(12.dp))
        }
        ZText(count, style = ZTheme.type.monoSmall, color = c.text2)
    }
}

@Composable
private fun Chain(t: RuleTrace, stats: RuleStats?) {
    val c = ZTheme.colors
    Column {
        Step(stringResource(R.string.rules_step_request), t.input, mono = true)
        val layer = t.layerIndex?.let { li -> stats?.layers?.firstOrNull { it.index == li } }
        if (layer != null) Step(stringResource(R.string.rules_step_layer, layer.index + 1, layer.name), t.rule, mono = true, badge = t.ruleNo?.let { "#" + ZFormat.grouped(it) })
        else Step(stringResource(R.string.rules_step_layer, (stats?.layers?.size ?: 7) + 1, stringResource(R.string.rules_other_traffic)), "MATCH", mono = true)
        when (t.policy) {
            "DIRECT" -> Step(stringResource(R.string.trace_step_exit), stringResource(R.string.common_direct), last = true)
            "REJECT" -> Step(stringResource(R.string.rules_step_result), stringResource(R.string.rules_blocked), last = true)
            else -> t.scene?.let { s ->
                Step(stringResource(R.string.rules_step_scene, s.displayName()), s.selected.name, region = s.selected.region, last = t.exitIp == null)
                t.exitIp?.let { Step(stringResource(R.string.rules_step_exit_ip), it, mono = true, last = true) }
            }
        }
        Spacer(Modifier.height(4.dp))
        ZText(stringResource(R.string.rules_took, ZFormat.micros(t.tookMicros)), style = ZTheme.type.caption, color = c.text3)
    }
}

@Composable
private fun Step(label: String, value: String, mono: Boolean = false, badge: String? = null, region: String? = null, last: Boolean = false) {
    val c = ZTheme.colors
    // Review L-P2-8: hollow dots joined by a vertical line; the final step is solid accent.
    Row(Modifier.fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
        Box(Modifier.width(9.dp).fillMaxHeight()) {
            if (!last) Box(Modifier.align(Alignment.TopCenter).padding(top = 14.dp).width(1.dp).fillMaxHeight().background(c.hairlineStrong))
            Box(Modifier.align(Alignment.TopCenter).padding(top = 5.dp).size(9.dp).then(if (last) Modifier.background(c.accent, CircleShape) else Modifier.border(1.5.dp, c.text3, CircleShape)))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f).padding(bottom = 12.dp)) {
            ZText(label, style = ZTheme.type.caption, color = c.text3)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (region != null) { ZRegionBadge(region); Spacer(Modifier.width(8.dp)) }
                ZText(value, style = if (mono) ZTheme.type.mono else ZTheme.type.body)
            }
        }
        if (badge != null) ZText(badge, style = ZTheme.type.monoSmall, color = c.text3)
    }
}

