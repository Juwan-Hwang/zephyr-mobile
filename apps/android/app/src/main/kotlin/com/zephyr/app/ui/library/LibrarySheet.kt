package com.zephyr.app.ui.library

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
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZStatTile
import com.zephyr.design.format.ZFormat
import com.zephyr.engine.Settings

enum class LibraryDest { Nodes, Subscriptions, Rules, Scenes, Settings, Widgets, TrustedWifi, LocalProxy }

/** Library sheet (prototype `libSheet`): 4 stat tiles + shortcuts. */
@Composable
fun BoxScope.LibrarySheet(visible: Boolean, onDismiss: () -> Unit, onOpen: (LibraryDest) -> Unit) {
    val e = AppGraph.engine
    val nodes by produceState(0L, visible) { if (visible) value = runCatching { e.nodeIndex().total }.getOrDefault(value) }
    val subs by produceState(0, visible) { if (visible) value = runCatching { e.subscriptionsSummary().count }.getOrDefault(value) }
    val rules by produceState(0L, visible) { if (visible) value = runCatching { e.ruleStats().total }.getOrDefault(value) }
    val scenes by remember { e.scenes() }.collectWhile(visible, emptyList())
    val settings by e.settings().collectAsState(Settings())
    ZSheet(visible, onDismiss, "资料库") {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ZStatTile(ZFormat.compactZh(nodes), "节点", Modifier.weight(1f)) { onOpen(LibraryDest.Nodes) }
            ZStatTile(ZFormat.grouped(subs.toLong()), "订阅", Modifier.weight(1f)) { onOpen(LibraryDest.Subscriptions) }
        }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ZStatTile(ZFormat.compactZh(rules), "规则", Modifier.weight(1f)) { onOpen(LibraryDest.Rules) }
            ZStatTile("${scenes.size}", "场景", Modifier.weight(1f)) { onOpen(LibraryDest.Scenes) }
        }
        Spacer(Modifier.height(20.dp))
        ZListGroup {
            ZSettingsRow("小组件与快捷开关", chevron = true, onClick = { onOpen(LibraryDest.Widgets) })
            ZDivider()
            ZSettingsRow("受信任的 Wi‑Fi", value = settings.trustedWifi.firstOrNull() ?: "无", chevron = true, onClick = { onOpen(LibraryDest.TrustedWifi) })
            ZDivider()
            ZSettingsRow("本地代理端口", value = if (settings.localProxyEnabled) "开" else "关", chevron = true, onClick = { onOpen(LibraryDest.LocalProxy) })
            ZDivider()
            ZSettingsRow("设置", chevron = true, onClick = { onOpen(LibraryDest.Settings) })
        }
        Box(Modifier.height(12.dp))
    }
}
