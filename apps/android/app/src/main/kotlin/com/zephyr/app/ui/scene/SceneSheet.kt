package com.zephyr.app.ui.scene

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.Scene

/** Scene detail (prototype `sceneSheet`): the funnel from subscription group to usable nodes. */
@Composable
fun BoxScope.SceneSheet(scene: Scene?, onDismiss: () -> Unit) {
    val c = ZTheme.colors
    ZSheet(scene != null, onDismiss, scene?.name ?: "") {
        val s = scene ?: return@ZSheet
        Row(Modifier.padding(horizontal = 22.dp), verticalAlignment = Alignment.Bottom) {
            ZText("${s.available}", style = ZTheme.type.number.copy(fontSize = ZTheme.type.hero.fontSize * 0.8f))
            Spacer(Modifier.width(8.dp))
            ZText("个可用节点", Modifier.padding(bottom = 8.dp), style = ZTheme.type.body, color = c.text3)
        }
        ZText("检测自 2 个订阅中的 512 个节点", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
        Spacer(Modifier.height(16.dp))
        // Funnel: each stage narrower, the last one highlighted.
        val stages = listOf("订阅分组 · Zephyr 优选" to 512, "全部" to 138, "延迟低于 300 ms" to 27, "可访问 GPT" to s.available + 3, "可访问 GPT、Claude 和 Gemini" to s.available)
        Column(Modifier.padding(horizontal = 16.dp)) {
            stages.forEachIndexed { i, (label, n) ->
                val f = 0.45f + 0.55f * (n.toFloat() / 512f).coerceIn(0f, 1f)
                Row(
                    Modifier.fillMaxWidth(f).padding(vertical = 3.dp)
                        .background(if (i == stages.lastIndex) c.accentSoft else c.surface3, ZTheme.shapes.control)
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ZText(label, Modifier.weight(1f), style = ZTheme.type.footnote, color = if (i == stages.lastIndex) c.accent else c.text2, maxLines = 1)
                    ZText("$n", style = ZTheme.type.monoSmall, color = if (i == stages.lastIndex) c.accent else c.text2)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        ZListGroup {
            ZSettingsRow("节点不可用时", value = "询问", chevron = true, onClick = {})
            s.exceptions.forEach { e -> ZDivider(); ZSettingsRow(e.app, value = "${e.node.name}（固定）", chevron = true, onClick = {}) }
            ZDivider()
            ZSettingsRow("检测频率", value = "每天（仅 Wi‑Fi）", chevron = true, onClick = {})
        }
        ZText(
            "优选结果仅保存在 Zephyr 中，订阅配置保持原样。" + (s.testedAt?.let { " 上次检测 ${ZFormat.ago(it, System.currentTimeMillis())}。" } ?: ""),
            Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3,
        )
    }
}
