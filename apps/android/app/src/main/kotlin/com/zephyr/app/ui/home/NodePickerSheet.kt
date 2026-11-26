package com.zephyr.app.ui.home

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.ui.common.NodeSort
import com.zephyr.app.ui.common.NodeSortControl
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZChip
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZEmptyState
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZLatency
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZRegionBadge
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZSkeleton
import com.zephyr.design.components.ZSurfaceLevel
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.ProxyMode

/** Home 「节点  <current>  <latency> ›」: one tap opens [NodePickerSheet]. */
@Composable
fun HomeNodeRow(ui: NodePickerUi, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val c = ZTheme.colors
    val title = stringResource(R.string.common_nodes)
    val name = ui.label ?: "—"
    ZCard(modifier.padding(horizontal = 16.dp), level = ZSurfaceLevel.S1, shape = RoundedCornerShape(18.dp)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp)
                .zPressable(row = true, onClick = onOpen)
                .padding(start = 18.dp, end = 12.dp, top = 14.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ZText(title, style = ZTheme.type.body, color = c.text3, maxLines = 1)
            Spacer(Modifier.width(16.dp))
            ZText(
                name, Modifier.weight(1f), style = ZTheme.type.body.copy(textAlign = androidx.compose.ui.text.style.TextAlign.End),
                color = if (ui.offline) c.text3 else c.text1, maxLines = 1,
            )
            if (ui.latencyMs != null) {
                Spacer(Modifier.width(10.dp))
                ZLatency(ui.latencyMs, style = ZTheme.type.mono)
            }
            Spacer(Modifier.width(6.dp))
            ZIcon(ZIcons.ChevronRight, tint = c.text3, size = 18.dp)
        }
    }
}

/**
 * The node sheet: the main group's members (rule) or the library (global), one tap switches. Header: 测速, group chips
 * when the subscription has several select groups (main first), search when the list is long, and the shared sort.
 */
@Composable
fun BoxScope.NodePickerSheet(
    ui: NodePickerUi,
    onDismiss: () -> Unit,
    onPick: (NodeSummary) -> Unit,
    onTest: () -> Unit,
    onGroup: (String) -> Unit,
    onQuery: (String) -> Unit,
    onSort: (NodeSort) -> Unit,
) {
    val canTest = !ui.testing && !ui.loading && !ui.offline && ui.rows.isNotEmpty()
    ZSheet(
        ui.open, onDismiss, stringResource(R.string.common_nodes),
        action = if (ui.offline) null else stringResource(if (ui.testing) R.string.home_scene_testing else R.string.nodes_detail_test),
        onAction = if (canTest) onTest else null,
        header = {
            if (ui.mode != ProxyMode.GLOBAL && ui.groups.size > 1) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ui.groups.forEach { g -> ZChip(g, g == ui.group, { onGroup(g) }) }
                }
                Spacer(Modifier.height(12.dp))
            }
            if (ui.searchable) {
                ZSearchField(ui.query, onQuery, stringResource(R.string.nodes_search_placeholder), Modifier.padding(horizontal = 16.dp))
                Spacer(Modifier.height(12.dp))
            }
            if (!ui.offline) {
                NodeSortControl(ui.sort, onSort, Modifier.padding(horizontal = 16.dp))
                Spacer(Modifier.height(12.dp))
            }
        },
    ) {
        val rows = ui.visibleRows
        when {
            ui.offline -> ZEmptyState(stringResource(R.string.groups_offline), Modifier.padding(vertical = 32.dp))
            ui.loading && rows.isEmpty() -> ZListGroup {
                repeat(4) { i ->
                    if (i > 0) ZDivider()
                    Row(Modifier.height(56.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { ZSkeleton(Modifier.width(160.dp).height(14.dp)) }
                }
            }
            rows.isEmpty() -> ZEmptyState(stringResource(if (ui.query.isNotBlank()) R.string.common_no_results else R.string.groups_none), Modifier.padding(vertical = 32.dp))
            else -> ZListGroup {
                rows.forEachIndexed { i, n ->
                    if (i > 0) ZDivider()
                    PickerRow(n, ui.latency[n.id] ?: n.latencyMs, ui.testing, current = ui.isCurrent(n), group = n.name in ui.groupNames, onClick = { onPick(n) })
                }
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun PickerRow(n: NodeSummary, latency: Int?, testing: Boolean, current: Boolean, group: Boolean, onClick: () -> Unit) {
    val c = ZTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .semantics { selected = current }
            .zPressable(row = true, onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val region = n.region.takeIf { !group && it.isNotBlank() && it != "UN" && n.protocol != "DIRECT" }
        Box(Modifier.width(40.dp)) { if (region != null) ZRegionBadge(region) }
        ZText(n.name, Modifier.weight(1f), style = ZTheme.type.body, maxLines = 1)
        if (latency != null || testing) {
            Spacer(Modifier.width(8.dp))
            ZLatency(latency, testing && latency == null, style = ZTheme.type.mono)
        }
        Spacer(Modifier.width(8.dp))
        Box(Modifier.width(20.dp), contentAlignment = Alignment.Center) {
            if (current) ZIcon(ZIcons.Check, tint = c.accentText, size = 18.dp, contentDescription = stringResource(R.string.common_current))
        }
    }
}
