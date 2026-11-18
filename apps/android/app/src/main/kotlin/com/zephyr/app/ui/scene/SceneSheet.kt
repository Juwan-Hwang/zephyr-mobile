package com.zephyr.app.ui.scene

import com.zephyr.app.ui.common.displayName
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSegmented
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeFunnel
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.SceneNodeFilter
import com.zephyr.engine.SceneSource
import com.zephyr.engine.Settings
import kotlinx.coroutines.flow.first

/**
 * Scene detail (prototype `sceneSheet`, 804–823): count, source segment (订阅分组 / Zephyr 优选), the candidate
 * pool sorted by latency, then the scene's settings. Everything shown comes from the engine. The funnel under the
 * segment is contract §15.c `nodeFunnel` (全部 → 已测速 → 可连通 → 延迟低于 300 ms, audit U11) and only shows for
 * Zephyr 优选; the prototype's per-service steps ("可访问 GPT") need probes core does not run, so they are left out.
 * Read-only rows have no chevron and no press state.
 */
@Composable
fun BoxScope.SceneSheet(
    scene: Scene?,
    onDismiss: () -> Unit,
    onPick: (Scene, NodeSummary) -> Unit = { _, _ -> },
    onSource: (Scene, SceneSource) -> Unit = { _, _ -> },
    retesting: Boolean = false,
    onRetest: (Scene) -> Unit = {},
) {
    val c = ZTheme.colors
    ZSheet(scene != null, onDismiss, scene?.displayName() ?: "") {
        val s = scene ?: return@ZSheet
        val subs by produceState(0, s.id) { value = runCatching { AppGraph.engine.subscriptions().first().size }.getOrDefault(0) }
        // The whole candidate pool: its size is the lede's "M 个节点"; the list shows the 12 fastest.
        val candidates by produceState(emptyList<NodeSummary>(), s.id, s.selected.id, s.source, s.nodeFilter) {
            value = runCatching { AppGraph.engine.sceneCandidates(s.id, null) }.getOrDefault(emptyList())
                .sortedBy { it.latencyMs ?: Int.MAX_VALUE }
        }
        val pool = candidates.take(12)
        val settings by AppGraph.engine.settings().collectAsState(Settings())
        Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
            ZText("${s.available}", style = ZTheme.type.number.copy(fontSize = ZTheme.type.hero.fontSize * 0.8f))
            Spacer(Modifier.width(8.dp))
            ZText(pluralStringResource(R.plurals.scene_available_unit, s.available), Modifier.padding(bottom = 8.dp), style = ZTheme.type.body, color = c.text3)
        }
        val pooled = s.source != SceneSource.SUBSCRIPTION_GROUP
        // §15.c/§15.e: same freshness window as the node list and scans (设置 › 结果保留).
        val funnel by produceState<NodeFunnel?>(null, s.id, s.testedAt, s.source, s.nodeFilter) {
            value = if (!pooled) null else runCatching {
                val ttl = AppGraph.engine.settings().first().latencyTtlHours.coerceAtLeast(1) * 3_600_000L
                AppGraph.engine.nodeFunnel(ttl, FUNNEL_THRESHOLD_MS)
            }.getOrNull()
        }
        // Audit #208 U33 (prototype / §15.c, iOS SceneSheet.lede): "检测自 N 个订阅中的 M 个节点" from the funnel; without
        // one (订阅分组, or no data yet) M is the scene's candidate pool.
        val f = funnel?.takeIf { pooled && it.poolSize > 0 }
        val lede = when {
            f != null -> stringResource(R.string.scene_tested_from_pool, f.sourceCount, ZFormat.grouped(f.poolSize.toLong()))
            subs > 0 && candidates.isNotEmpty() -> stringResource(R.string.scene_tested_from_pool, subs, ZFormat.grouped(candidates.size.toLong()))
            subs > 0 -> pluralStringResource(R.plurals.scene_tested_from, subs, subs)
            else -> null
        }
        if (lede != null) ZText(lede, Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
        Spacer(Modifier.height(16.dp))
        ZSegmented(
            listOf(stringResource(R.string.common_source_group), stringResource(R.string.common_source_auto)), if (pooled) 1 else 0,
            { i -> val want = if (i == 1) SceneSource.AUTO else SceneSource.SUBSCRIPTION_GROUP; if (want != s.source) onSource(s, want) },
            Modifier.padding(horizontal = 16.dp),
        )
        f?.let { pf ->
            Spacer(Modifier.height(18.dp))
            SceneFunnel(funnelSteps(pf))
            Spacer(Modifier.height(6.dp))
        }
        Spacer(Modifier.height(12.dp))
        if (pool.isNotEmpty()) {
            ZListGroup {
                pool.forEachIndexed { i, n ->
                    if (i > 0) ZDivider()
                    val fixed = s.exceptions.firstOrNull { it.node.id == n.id }
                    ZSettingsRow(
                        n.name,
                        value = listOfNotNull(fixed?.let { stringResource(R.string.scene_pinned_for, it.app) }, n.latencyMs?.let { "$it ms" }).joinToString("  ").ifEmpty { null },
                        onClick = if (n.id == s.selected.id) null else ({ onPick(s, n) }),
                        trailing = if (n.id == s.selected.id) ({ ZText(stringResource(R.string.common_current), style = ZTheme.type.footnote, color = c.accent) }) else null,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
        }
        ZListGroup {
            ZSettingsRow(stringResource(R.string.scene_when_unavailable), value = stringResource(if (s.kind == SceneKind.AI) R.string.scene_ask else R.string.scene_auto_switch))
            // §15.h: set by the command "视频只用 4K 节点"; candidates and auto-pick above are already filtered.
            if (s.nodeFilter == SceneNodeFilter.UHD) { ZDivider(); ZSettingsRow(stringResource(R.string.scene_node_scope), value = stringResource(R.string.scene_uhd_only)) }
            s.exceptions.forEach { e -> ZDivider(); ZSettingsRow(e.app, value = stringResource(R.string.scene_pinned_value, e.node.name)) }
            ZDivider()
            // Audit #208 U33: results older than 设置 › 结果保留 are re-tested; 24 h reads "每天" (iOS retestFrequency).
            ZSettingsRow(stringResource(R.string.scene_test_frequency), value = retestFrequency(settings))
            ZDivider()
            // Prototype 10: re-test the scene's pool; progress shows on the home row and section header.
            ZSettingsRow(stringResource(if (retesting) R.string.common_retesting else R.string.scene_retest), onClick = if (retesting) null else ({ onRetest(s) }))
        }
        ZText(
            stringResource(R.string.scene_note).let { note ->
                s.testedAt?.let { stringResource(R.string.scene_note_tested, note, ZFormat.ago(LocalResources.current, it, com.zephyr.app.ui.common.LocalNow.current(), inline = true)) } ?: note
            },
            Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3,
        )
    }
}

/** Funnel threshold: the prototype's "延迟低于 300 ms" (contract §15.c default). */
private const val FUNNEL_THRESHOLD_MS = 300

@Composable
private fun retestFrequency(s: Settings): String {
    val hours = s.latencyTtlHours.takeIf { it > 0 } ?: 24 // §15.e: 0 means the default 24 h
    val base = if (hours == 24) stringResource(R.string.scene_test_daily) else pluralStringResource(R.plurals.scene_test_every_hours, hours, hours)
    return if (s.testOnWifiOnly) stringResource(R.string.scene_test_wifi_only, base) else base
}
