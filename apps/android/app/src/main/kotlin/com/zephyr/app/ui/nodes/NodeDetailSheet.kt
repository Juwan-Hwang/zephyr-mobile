package com.zephyr.app.ui.nodes

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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZLatency
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZRegionBadge
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeDetail
import com.zephyr.engine.NodeSummary

/**
 * Node detail (audit U12; iOS `NodeDetailSheet`): protocol, latency, server:port, subscription and route, plus
 * "测速" for this one node. The server comes from `node(id)` (already redacted by the engine); "—" until it loads.
 */
@Composable
fun BoxScope.NodeDetailSheet(
    node: NodeSummary?,
    latency: Int?,
    testing: Boolean,
    load: suspend (Long) -> NodeDetail?,
    onTest: (NodeSummary) -> Unit,
    onDismiss: () -> Unit,
) {
    val c = ZTheme.colors
    ZSheet(node != null, onDismiss, node?.name ?: "") {
        val n = node ?: return@ZSheet
        val detail by produceState<NodeDetail?>(null, n.id) { value = load(n.id) }
        Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.CenterVertically) {
            ZRegionBadge(n.region)
            Spacer(Modifier.width(12.dp))
            ZText(listOfNotNull(n.city, n.region.takeIf { n.city == null }).joinToString(), style = ZTheme.type.footnote, color = c.text3)
        }
        Spacer(Modifier.height(16.dp))
        ZListGroup {
            ZSettingsRow(stringResource(R.string.nodes_detail_protocol), value = n.protocol.ifEmpty { "—" })
            ZDivider()
            val ms = latency ?: n.latencyMs ?: detail?.latencyMs
            ZSettingsRow(
                stringResource(R.string.nodes_detail_latency),
                trailing = { ZLatency(ms, testing, style = ZTheme.type.mono) },
            )
            ZDivider()
            ZSettingsRow(stringResource(R.string.nodes_detail_server), value = detail?.let { "${it.server}:${it.port}" } ?: "—")
            ZDivider()
            ZSettingsRow(stringResource(R.string.rules_kind_subscription), value = detail?.subscription?.ifEmpty { null } ?: "—")
            if (n.tag != null) {
                ZDivider()
                ZSettingsRow(stringResource(R.string.nodes_detail_route), value = listOfNotNull(n.carrier, n.tag).joinToString(" · "))
            }
        }
        Spacer(Modifier.height(12.dp))
        ZListGroup {
            ZSettingsRow(
                stringResource(if (testing) R.string.home_scene_testing else R.string.nodes_detail_test),
                onClick = if (testing) null else ({ onTest(n) }),
                trailing = null,
            )
        }
        Spacer(Modifier.height(12.dp))
    }
}
