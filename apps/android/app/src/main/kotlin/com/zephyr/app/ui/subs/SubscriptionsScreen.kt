package com.zephyr.app.ui.subs

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIconButton
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZProgressBar
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToggle
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.Settings
import com.zephyr.engine.SubscriptionsSummary
import kotlinx.coroutines.launch

@Composable
fun SubscriptionsScreen(back: String = "资料库", onBack: () -> Unit, onImport: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    val subs by engine.subscriptions().collectAsState(emptyList())
    val settings by engine.settings().collectAsState(Settings())
    val summary by produceState(SubscriptionsSummary(0, 0), subs) { value = engine.subscriptionsSummary() }
    val scope = rememberCoroutineScope()
    val clock = com.zephyr.app.ui.common.LocalNow.current
    // Ticks once a minute so "2 小时前" / "26 天后到期" stay true while the page is open (review L-P2-9).
    val now by androidx.compose.runtime.produceState(clock()) { while (true) { kotlinx.coroutines.delay(60_000); value = clock() } }
    var updating by remember { mutableStateOf(false) }

    PageScaffold(back, "订阅", onBack, trailing = { ZIconButton(ZIcons.Plus, "添加订阅", onImport, tint = c.accent) }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
                ZText("${summary.count}", style = ZTheme.type.hero.copy(fontSize = ZTheme.type.hero.fontSize * 0.86f))
                Spacer(Modifier.width(8.dp))
                ZText("个 · 每 ${settings.autoUpdateHours} 小时更新", Modifier.padding(bottom = 10.dp), style = ZTheme.type.body, color = c.text3)
            }
            Spacer(Modifier.height(16.dp))
            subs.firstOrNull { it.lastDiff != null }?.let { s ->
                val d = s.lastDiff!!
                ZCard(Modifier.padding(horizontal = 16.dp), padding = 18.dp) {
                    Row {
                        ZText("${s.name} ${if (updating) "正在更新…" else "已更新"}", Modifier.weight(1f), style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
                        s.updatedAt?.let { ZText(ZFormat.ago(it, now), style = ZTheme.type.footnote, color = c.text3) }
                    }
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                        Delta("+" + ZFormat.grouped(d.addedNodes), "节点", c.connected)
                        Delta("−" + ZFormat.grouped(d.removedNodes), "节点", c.danger)
                        Delta(ZFormat.grouped(d.ruleChanges), "规则变更", c.text1)
                    }
                    Spacer(Modifier.height(14.dp)); ZDivider(inset = false); Spacer(Modifier.height(14.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(7.dp).background(c.connected, CircleShape)); Spacer(Modifier.width(10.dp))
                        ZText(listOfNotNull(if (d.overridesKept) "覆写已保留" else null, if (d.scenesRetested) "场景池已重新检测" else null).joinToString(" · "), style = ZTheme.type.callout, color = c.text2)
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            ZSectionHeader("流量", trailing = "本月")
            ZCard(Modifier.padding(horizontal = 16.dp)) {
                subs.forEachIndexed { i, s ->
                    if (i > 0) ZDivider(inset = false)
                    val soon = (s.expiresAt ?: Long.MAX_VALUE) - now < 3 * 86_400_000L
                    Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            ZText(s.name, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
                            ZText("${ZFormat.grouped(s.nodeCount)} 个节点" + (s.expiresAt?.let { " · " + ZFormat.expires(it, now) } ?: ""), style = ZTheme.type.footnote, color = c.text3)
                            Spacer(Modifier.height(10.dp))
                            val u = s.usedBytes; val t = s.totalBytes
                            ZProgressBar(if (u != null && t != null && t > 0) u.toFloat() / t else 0f, color = if (soon) c.warning else c.text3)
                        }
                        Spacer(Modifier.width(24.dp))
                        Column(horizontalAlignment = Alignment.End) {
                            ZText(s.remainingBytes?.let(ZFormat::bytesText) ?: "—", style = ZTheme.type.mono)
                            ZText("剩余", style = ZTheme.type.footnote, color = c.text3)
                        }
                    }
                }
                val others = summary.count - subs.size
                if (others > 0) {
                    ZDivider(inset = false)
                    ZSettingsRow("其他 $others 个", subtitle = "${ZFormat.grouped(summary.totalNodes - subs.sumOf { it.nodeCount })} 个节点")
                }
            }
            Spacer(Modifier.height(18.dp))
            ZSectionHeader("更新")
            ZListGroup {
                ZSettingsRow("自动更新", value = "每 ${settings.autoUpdateHours} 小时", chevron = true, onClick = {
                    val next = when (settings.autoUpdateHours) { 6 -> 12; 12 -> 24; else -> 6 }
                    scope.launch { engine.updateSettings(settings.copy(autoUpdateHours = next)) }
                })
                ZDivider()
                ZSettingsRow("仅在 Wi‑Fi 下更新", checked = settings.updateOnWifiOnly, onCheckedChange = { v -> scope.launch { engine.updateSettings(settings.copy(updateOnWifiOnly = v)) } })
                ZDivider()
                ZSettingsRow("更新前显示更改", checked = settings.showChangesBeforeUpdate, onCheckedChange = { v -> scope.launch { engine.updateSettings(settings.copy(showChangesBeforeUpdate = v)) } })
                ZDivider()
                ZSettingsRow("立即全部更新", onClick = { scope.launch { updating = true; runCatching { engine.updateAll() }; updating = false } }, value = if (updating) "正在更新…" else null)
            }
            Spacer(Modifier.height(48.dp))
        }
    }
}

@Composable
private fun Delta(v: String, label: String, color: androidx.compose.ui.graphics.Color) {
    Column {
        ZText(v, style = ZTheme.type.number, color = color)
        ZText(label, style = ZTheme.type.footnote, color = ZTheme.colors.text3)
    }
}
