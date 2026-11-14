package com.zephyr.app.ui.settings

import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
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
fun SettingsScreen(back: String, onLogs: () -> Unit = {}, onBack: () -> Unit) {
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
                ZSettingsRow("按需连接", checked = s.onDemand, onCheckedChange = { v -> set { it.copy(onDemand = v) } })
                ZDivider()
                ZSettingsRow("受信任的 Wi‑Fi", subtitle = "连接后自动断开", value = s.trustedWifi.joinToString("、").ifEmpty { "无" })
                ZDivider()
                ChoiceRow(
                    "本地代理端口", listOf(true to "开", false to "关"), s.localProxyEnabled,
                    onSelect = { v -> set { it.copy(localProxyEnabled = v) } },
                    subtitle = "127.0.0.1:${s.localProxyPort}" + if (s.localProxyAuth) " · 需要密码" else "",
                )
            }
            ZSectionHeader("检测", Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow("仅在 Wi‑Fi 下测速", checked = s.testOnWifiOnly, onCheckedChange = { v -> set { it.copy(testOnWifiOnly = v) } })
                ZDivider()
                ChoiceRow(
                    "结果保留", (listOf(6, 24, 72) + s.latencyTtlHours).distinct().sorted().map { it to "$it 小时" }, s.latencyTtlHours,
                    onSelect = { h -> set { it.copy(latencyTtlHours = h) } },
                )
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
                ChoiceRow(
                    "外观", listOf(Appearance.SYSTEM to "跟随系统", Appearance.DARK to "深色", Appearance.LIGHT to "浅色"), s.appearance,
                    onSelect = { a -> set { it.copy(appearance = a) } },
                )
                ZDivider()
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    ZText("强调色", Modifier.weight(1f), style = ZTheme.type.body)
                    // Review L-P1-5: 28 dp dot inside a 44 dp radio target, Chinese names, selected semantics, one group.
                    Row(Modifier.selectableGroup(), horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                        Accent.entries.forEach { a ->
                            val z = ZAccent.valueOf(a.name)
                            val col = if (c.isDark) z.darkVariant() else z.color
                            Box(
                                Modifier.size(44.dp)
                                    .selectable(selected = s.accent == a, role = Role.RadioButton) { set { it.copy(accent = a) } }
                                    .semantics { contentDescription = accentName(a) },
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    Modifier.size(28.dp).clip(CircleShape).background(col)
                                        .then(if (s.accent == a) Modifier.border(2.dp, c.text1, CircleShape) else Modifier),
                                )
                            }
                        }
                    }
                }
            }
            ZSectionHeader("隐私", Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow("共享诊断数据", checked = s.shareDiagnostics, onCheckedChange = { v -> set { it.copy(shareDiagnostics = v) } })
            }
            ZSectionHeader("诊断", Modifier.padding(top = 12.dp))
            ZListGroup {
                ZSettingsRow("日志", chevron = true, onClick = onLogs)
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

private fun accentName(a: Accent): String = when (a.name) {
    "BLUE" -> "蓝色"; "GREEN" -> "绿色"; "ORANGE" -> "橙色"; "PINK" -> "粉色"; "PURPLE" -> "紫色"
    "RED" -> "红色"; "TEAL" -> "青色"; "INDIGO" -> "靛蓝"; "YELLOW" -> "黄色"; "GRAPHITE" -> "石墨"
    else -> a.name.lowercase()
}
