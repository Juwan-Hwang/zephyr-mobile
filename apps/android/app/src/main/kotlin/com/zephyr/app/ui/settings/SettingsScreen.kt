package com.zephyr.app.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.zephyr.app.BuildConfig
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToggle
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.theme.darkVariant
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.Accent
import com.zephyr.engine.Appearance
import com.zephyr.engine.Settings
import com.zephyr.engine.StorageInfo
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(back: String, onBack: () -> Unit) {
    val engine = AppGraph.engine
    val c = ZTheme.colors
    val s by engine.settings().collectAsState(Settings())
    val storage by produceState(StorageInfo(0, 0, 0)) { value = engine.storage() }
    val scope = rememberCoroutineScope()
    fun set(f: (Settings) -> Settings) = scope.launch { engine.updateSettings(f(s)) }

    PageScaffold(back, "设置", onBack) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            ZSectionHeader("连接")
            ZListGroup {
                ZSettingsRow("按需连接", trailing = { ZToggle(s.onDemand, { v -> set { it.copy(onDemand = v) } }) })
                ZDivider()
                ZSettingsRow("受信任的 Wi‑Fi", subtitle = "连接后自动断开", value = s.trustedWifi.joinToString("、").ifEmpty { "无" }, chevron = true, onClick = {})
                ZDivider()
                ZSettingsRow(
                    "本地代理端口", subtitle = "127.0.0.1:${s.localProxyPort}" + if (s.localProxyAuth) " · 需要密码" else "",
                    value = if (s.localProxyEnabled) "开" else "关", chevron = true,
                    onClick = { set { it.copy(localProxyEnabled = !it.localProxyEnabled) } },
                )
            }
            ZSectionHeader("检测", Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow("仅在 Wi‑Fi 下测速", trailing = { ZToggle(s.testOnWifiOnly, { v -> set { it.copy(testOnWifiOnly = v) } }) })
                ZDivider()
                ZSettingsRow("结果保留", value = "${s.latencyTtlHours} 小时", chevron = true, onClick = {
                    set { it.copy(latencyTtlHours = when (it.latencyTtlHours) { 6 -> 24; 24 -> 72; else -> 6 }) }
                })
            }
            ZSectionHeader("存储", Modifier.padding(top = 12.dp))
            ZListGroup {
                Column(Modifier.padding(20.dp)) {
                    ZText("节点与规则", style = ZTheme.type.body)
                    Spacer(Modifier.height(12.dp))
                    StorageBar(storage)
                    Spacer(Modifier.height(8.dp))
                    ZText("节点 ${ZFormat.bytesText(storage.nodesBytes)} · 规则 ${ZFormat.bytesText(storage.rulesBytes)} · 可用 ${ZFormat.bytesText(storage.freeBytes)}", style = ZTheme.type.footnote, color = c.text3)
                }
            }
            ZSectionHeader("外观", Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow("外观", value = when (s.appearance) { Appearance.SYSTEM -> "跟随系统"; Appearance.DARK -> "深色"; Appearance.LIGHT -> "浅色" }, chevron = true, onClick = {
                    set { it.copy(appearance = Appearance.entries[(it.appearance.ordinal + 1) % Appearance.entries.size]) }
                })
                ZDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    ZText("强调色", Modifier.weight(1f), style = ZTheme.type.body)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Accent.entries.forEach { a ->
                            val z = ZAccent.valueOf(a.name)
                            val col = if (c.isDark) z.darkVariant() else z.color
                            Box(
                                Modifier.size(28.dp).clip(CircleShape).background(col)
                                    .then(if (s.accent == a) Modifier.border(2.dp, c.text1, CircleShape) else Modifier)
                                    .zPressable(haptic = true, label = a.name) { set { it.copy(accent = a) } },
                            )
                        }
                    }
                }
            }
            ZSectionHeader("隐私", Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow("共享诊断数据", trailing = { ZToggle(s.shareDiagnostics, { v -> set { it.copy(shareDiagnostics = v) } }) })
            }
            ZText("订阅、节点与流量数据仅保存在此设备上。", Modifier.padding(horizontal = 22.dp, vertical = 10.dp), style = ZTheme.type.footnote, color = c.text3)
            ZText("Zephyr ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", Modifier.fillMaxWidth().padding(vertical = 24.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text4)
        }
    }
}

@Composable
private fun StorageBar(s: StorageInfo) {
    val c = ZTheme.colors
    val total = (s.nodesBytes + s.rulesBytes + s.freeBytes).coerceAtLeast(1).toFloat()
    Row(Modifier.fillMaxWidth().height(6.dp).clip(ZTheme.shapes.pill).background(c.surface4)) {
        if (s.nodesBytes > 0) Box(Modifier.weight(s.nodesBytes / total).fillMaxHeight().background(c.accent))
        if (s.rulesBytes > 0) Box(Modifier.weight(s.rulesBytes / total).fillMaxHeight().background(c.text3))
        if (s.freeBytes > 0) Box(Modifier.weight(s.freeBytes / total).fillMaxHeight())
    }
}
