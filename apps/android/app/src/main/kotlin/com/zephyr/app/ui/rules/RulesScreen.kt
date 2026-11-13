package com.zephyr.app.ui.rules

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
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.border
import androidx.compose.ui.unit.sp
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.PageScaffold
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
fun RulesScreen(initial: String, back: String = "资料库", onBack: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    var q by remember { mutableStateOf(initial) }
    val stats by produceState<RuleStats?>(null) { value = engine.ruleStats() }
    val trace by produceState<RuleTrace?>(null, q) {
        if (q.isBlank()) { value = null; return@produceState }
        if (q != initial) delay(60) // debounce typing, not the deep-linked first query
        value = runCatching { engine.testRule(q) }.getOrNull()
    }
    PageScaffold(back = back, title = "规则", onBack = onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
                ZText(ZFormat.grouped(stats?.total ?: 0), style = ZTheme.type.hero.copy(fontSize = ZTheme.type.hero.fontSize * 0.86f))
                Spacer(Modifier.width(8.dp))
                ZText("条", Modifier.padding(bottom = 10.dp), style = ZTheme.type.body, color = c.text3)
            }
            ZText("${stats?.layers?.size ?: 7} 层 · 已编译 · 磁盘占用 ${ZFormat.bytesText(stats?.diskBytes ?: 0)}", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
            Spacer(Modifier.height(18.dp))
            ZSearchField(q, { q = it }, "测试域名或 IP", Modifier.padding(horizontal = 16.dp))
            Spacer(Modifier.height(12.dp))
            ZCard(Modifier.padding(horizontal = 16.dp), padding = 18.dp) {
                AnimatedContent(trace, transitionSpec = { fadeIn(ZAnim.standard()) togetherWith fadeOut(ZAnim.micro()) }, label = "trace") { t ->
                    if (t == null) ZText("输入域名或 IP，查看匹配的规则与出口。", style = ZTheme.type.footnote, color = c.text3)
                    else Chain(t, stats)
                }
            }
            Spacer(Modifier.height(20.dp))
            ZSectionHeader("匹配顺序", trailing = "从上到下")
            ZCard(Modifier.padding(horizontal = 16.dp)) {
                val hit = trace
                stats?.layers?.forEachIndexed { i, l ->
                    if (i > 0) ZDivider(inset = false)
                    LayerRow(i + 1, l.name, l.note, kindLabel(l.kind), ZFormat.grouped(l.count), hit != null && hit.layerIndex == l.index, accent = l.kind == LayerKind.OVERRIDE)
                }
                ZDivider(inset = false)
                LayerRow((stats?.layers?.size ?: 7) + 1, "其余流量", "MATCH", null, "其他", trace != null && trace!!.layerIndex == null, false)
            }
            ZText(
                "规则集在设备上编译为只读索引，按需从磁盘读取。订阅更新时，覆写保持不变。",
                Modifier.padding(horizontal = 22.dp, vertical = 14.dp), style = ZTheme.type.footnote, color = c.text3,
            )
            Spacer(Modifier.height(40.dp))
        }
    }
}

private fun kindLabel(k: LayerKind) = when (k) { LayerKind.OVERRIDE -> "覆写"; LayerKind.SUBSCRIPTION -> "订阅"; LayerKind.DOMAIN -> "域名"; LayerKind.IP -> "IP" }

@Composable
private fun LayerRow(ix: Int, name: String, note: String, kind: String?, count: String, hit: Boolean, accent: Boolean) {
    val c = ZTheme.colors
    val bg by animateColorAsState(if (hit) c.accent.copy(alpha = 0.09f) else c.bg.copy(alpha = 0f), ZAnim.standard(), label = "hit")
    Row(Modifier.fillMaxWidth().background(bg).padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        ZText("$ix", Modifier.width(24.dp), style = ZTheme.type.mono, color = if (hit) c.accent else c.text3)
        Column(Modifier.weight(1f)) {
            ZText(name, style = ZTheme.type.body, maxLines = 1)
            ZText(note, style = ZTheme.type.caption, color = c.text3, maxLines = 1)
        }
        if (kind != null) {
            // Review L-P2-8: prototype layer tag is a 1px outline, 10px mono.
            ZText(kind, Modifier.border(1.dp, if (accent) c.accent else c.hairlineStrong, ZTheme.shapes.control).padding(horizontal = 7.dp, vertical = 2.dp), style = ZTheme.type.monoSmall.copy(fontSize = 10.sp), color = if (accent) c.accent else c.text2)
            Spacer(Modifier.width(12.dp))
        }
        ZText(count, style = ZTheme.type.monoSmall, color = c.text2)
    }
}

@Composable
private fun Chain(t: RuleTrace, stats: RuleStats?) {
    val c = ZTheme.colors
    Column {
        Step("请求", t.input, mono = true)
        val layer = t.layerIndex?.let { li -> stats?.layers?.firstOrNull { it.index == li } }
        if (layer != null) Step("第 ${layer.index + 1} 层 · ${layer.name}", t.rule, mono = true, badge = t.ruleNo?.let { "#" + ZFormat.grouped(it) })
        else Step("第 ${(stats?.layers?.size ?: 7) + 1} 层 · 其余流量", "MATCH", mono = true)
        when (t.policy) {
            "DIRECT" -> Step("出口", "直连", last = true)
            "REJECT" -> Step("结果", "已拦截", last = true)
            else -> t.scene?.let { s ->
                Step("场景 · ${s.name}", s.selected.name, region = s.selected.region, last = t.exitIp == null)
                t.exitIp?.let { Step("出口 IP", it, mono = true, last = true) }
            }
        }
        Spacer(Modifier.height(4.dp))
        ZText("用时 ${ZFormat.micros(t.tookMicros)}", style = ZTheme.type.caption, color = c.text3)
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

