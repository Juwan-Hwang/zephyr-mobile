package com.zephyr.app.ui.scene

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSegmented
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.SceneSource
import kotlinx.coroutines.flow.first

/**
 * Scene detail (prototype `sceneSheet`, 804–823): count, source segment (订阅分组 / Zephyr 优选), the candidate
 * pool sorted by latency, then the scene's settings. Everything shown comes from the engine; the prototype's
 * funnel needs per-stage counts the contract does not carry yet, so it is left out rather than made up
 * (review H-P1-8). Read-only rows have no chevron and no press state.
 */
@Composable
fun BoxScope.SceneSheet(
    scene: Scene?,
    onDismiss: () -> Unit,
    onPick: (Scene, NodeSummary) -> Unit = { _, _ -> },
    onSource: (Scene, SceneSource) -> Unit = { _, _ -> },
) {
    val c = ZTheme.colors
    ZSheet(scene != null, onDismiss, scene?.name ?: "") {
        val s = scene ?: return@ZSheet
        val subs by produceState(0, s.id) { value = runCatching { AppGraph.engine.subscriptions().first().size }.getOrDefault(0) }
        val pool by produceState(emptyList<NodeSummary>(), s.id, s.selected.id, s.source) {
            value = runCatching { AppGraph.engine.sceneCandidates(s.id, null) }.getOrDefault(emptyList())
                .sortedBy { it.latencyMs ?: Int.MAX_VALUE }.take(12)
        }
        Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
            ZText("${s.available}", style = ZTheme.type.number.copy(fontSize = ZTheme.type.hero.fontSize * 0.8f))
            Spacer(Modifier.width(8.dp))
            ZText("个可用节点", Modifier.padding(bottom = 8.dp), style = ZTheme.type.body, color = c.text3)
        }
        if (subs > 0) ZText("检测自 $subs 个订阅", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
        Spacer(Modifier.height(16.dp))
        val pooled = s.source != SceneSource.SUBSCRIPTION_GROUP
        ZSegmented(
            listOf("订阅分组", "Zephyr 优选"), if (pooled) 1 else 0,
            { i -> val want = if (i == 1) SceneSource.AUTO else SceneSource.SUBSCRIPTION_GROUP; if (want != s.source) onSource(s, want) },
            Modifier.padding(horizontal = 16.dp),
        )
        Spacer(Modifier.height(12.dp))
        if (pool.isNotEmpty()) {
            ZListGroup {
                pool.forEachIndexed { i, n ->
                    if (i > 0) ZDivider()
                    val fixed = s.exceptions.firstOrNull { it.node.id == n.id }
                    ZSettingsRow(
                        n.name,
                        value = listOfNotNull(fixed?.let { "${it.app} 固定" }, n.latencyMs?.let { "$it ms" }).joinToString("  ").ifEmpty { null },
                        onClick = if (n.id == s.selected.id) null else ({ onPick(s, n) }),
                        trailing = if (n.id == s.selected.id) ({ ZText("当前", style = ZTheme.type.footnote, color = c.accent) }) else null,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
        }
        ZListGroup {
            ZSettingsRow("节点不可用时", value = if (s.kind == SceneKind.AI) "询问" else "自动切换")
            s.exceptions.forEach { e -> ZDivider(); ZSettingsRow(e.app, value = "${e.node.name}（固定）") }
        }
        ZText(
            "优选结果仅保存在 Zephyr 中，订阅配置保持原样。" + (s.testedAt?.let { " 上次检测 ${ZFormat.ago(it, com.zephyr.app.ui.common.LocalNow.current())}。" } ?: ""),
            Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3,
        )
    }
}
