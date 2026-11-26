package com.zephyr.app.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZChip
import com.zephyr.engine.NodeSummary
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/** Order of a node list. One choice for the Home node sheet, 策略组 members and the 节点 library. */
enum class NodeSort {
    /** As the subscription lists them. */
    DEFAULT,
    /** Fastest first; untested, then timed out, last. */
    LATENCY,
    /** By name in the device's language. */
    NAME;

    companion object {
        fun parse(raw: String?): NodeSort = entries.firstOrNull { it.name == raw } ?: DEFAULT
    }
}

/** Pure ordering shared by the three lists (unit-tested). Stable: equal keys keep the subscription's order. */
object NodeSorting {
    /** [latencyOf] overrides a row's own reading (results that arrived after the row was read). */
    fun sort(rows: List<NodeSummary>, sort: NodeSort, latencyOf: (NodeSummary) -> Int? = { it.latencyMs }): List<NodeSummary> = when (sort) {
        NodeSort.DEFAULT -> rows
        NodeSort.LATENCY -> rows.sortedWith(compareBy({ latencyRank(latencyOf(it)) }, { latencyOf(it)?.takeIf { ms -> ms >= 0 } ?: 0 }))
        NodeSort.NAME -> {
            val collator = java.text.Collator.getInstance().apply { strength = java.text.Collator.SECONDARY }
            rows.sortedWith { a, b -> collator.compare(a.name, b.name) }
        }
    }

    /** 0 = has a reading, 1 = untested, 2 = timed out. */
    private fun latencyRank(ms: Int?): Int = when {
        ms == null -> 1
        ms < 0 -> 2
        else -> 0
    }
}

/** The stored choice; in-memory when there is no settings store (screenshot tests, previews). */
object NodeSortPref {
    private val memory = MutableStateFlow(NodeSort.DEFAULT)

    val flow: Flow<NodeSort> get() = if (AppGraph.hasSettings) AppGraph.settings.nodeSort else memory

    fun set(sort: NodeSort) {
        if (AppGraph.hasSettings) AppGraph.appScope.launch { AppGraph.settings.setNodeSort(sort) } else memory.value = sort
    }
}

/** 默认顺序 / 延迟 / 名称, the same three chips at the top of every node list. */
@Composable
fun NodeSortControl(sort: NodeSort, onSort: (NodeSort) -> Unit, modifier: Modifier = Modifier) {
    val label = stringResource(R.string.nodes_sort)
    Row(
        modifier.semantics { contentDescription = label; isTraversalGroup = true },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        NodeSort.entries.forEach { s -> ZChip(stringResource(labelOf(s)), s == sort, { onSort(s) }) }
    }
}

private fun labelOf(s: NodeSort): Int = when (s) {
    NodeSort.DEFAULT -> R.string.nodes_sort_default
    NodeSort.LATENCY -> R.string.nodes_detail_latency
    NodeSort.NAME -> R.string.nodes_sort_name
}
