package com.zephyr.app.ui.library

import com.zephyr.app.R
import com.zephyr.app.ui.common.collectWhile
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZSurfaceLevel
import androidx.compose.foundation.shape.RoundedCornerShape
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZStatTile
import com.zephyr.design.format.ZFormat
import com.zephyr.engine.Settings

enum class LibraryDest { Nodes, Subscriptions, Rules, Scenes, Groups, Settings, Widgets, TrustedWifi, LocalProxy }

/** Library sheet (prototype `libSheet`): 4 stat tiles + shortcuts. */
@Composable
fun BoxScope.LibrarySheet(visible: Boolean, onDismiss: () -> Unit, onOpen: (LibraryDest) -> Unit) {
    val e = AppGraph.engine
    // Review L-P2-2: counts re-read whenever the subscription list changes while the sheet is open (import / update /
    // delete), not just once per open. The list flow is only collected while visible (H-P1-6).
    val subList by remember { e.subscriptions() }.collectWhile(visible, emptyList())
    val nodes by produceState(0L, visible, subList) { if (visible) value = runCatching { e.nodeIndex().total }.getOrDefault(value) }
    val subs by produceState(0, visible, subList) { if (visible) value = runCatching { e.subscriptionsSummary().count }.getOrDefault(value) }
    val rules by produceState(0L, visible, subList) { if (visible) value = runCatching { e.ruleStats().total }.getOrDefault(value) }
    val scenes by remember { e.scenes() }.collectWhile(visible, emptyList())
    val settings by e.settings().collectAsState(Settings())
    val res = LocalResources.current
    ZSheet(visible, onDismiss, stringResource(R.string.common_library)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ZStatTile(ZFormat.compact(res, nodes), stringResource(R.string.common_nodes), Modifier.weight(1f)) { onOpen(LibraryDest.Nodes) }
            ZStatTile(ZFormat.grouped(subs.toLong()), stringResource(R.string.common_subscriptions), Modifier.weight(1f)) { onOpen(LibraryDest.Subscriptions) }
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ZStatTile(ZFormat.compact(res, rules), stringResource(R.string.common_rules), Modifier.weight(1f)) { onOpen(LibraryDest.Rules) }
            ZStatTile("${scenes.size}", stringResource(R.string.common_scenes), Modifier.weight(1f)) { onOpen(LibraryDest.Scenes) }
        }
        Spacer(Modifier.height(20.dp))
        ZListGroup(level = ZSurfaceLevel.S1, shape = RoundedCornerShape(18.dp)) {
            // #208: the subscription's own policy groups (contract §4), to pick a node in a select group.
            ZSettingsRow(stringResource(R.string.library_groups), chevron = true, onClick = { onOpen(LibraryDest.Groups) })
            ZDivider()
            ZSettingsRow(stringResource(R.string.library_widgets), chevron = true, onClick = { onOpen(LibraryDest.Widgets) })
            ZDivider()
            ZSettingsRow(stringResource(R.string.settings_trusted_wifi), value = settings.trustedWifi.firstOrNull() ?: stringResource(R.string.common_none), chevron = true, onClick = { onOpen(LibraryDest.TrustedWifi) })
            ZDivider()
            ZSettingsRow(stringResource(R.string.settings_local_proxy), value = stringResource(if (settings.localProxyEnabled) R.string.common_on else R.string.common_off), chevron = true, onClick = { onOpen(LibraryDest.LocalProxy) })
            ZDivider()
            ZSettingsRow(stringResource(R.string.common_settings), chevron = true, onClick = { onOpen(LibraryDest.Settings) })
        }
        Box(Modifier.height(12.dp))
    }
}
