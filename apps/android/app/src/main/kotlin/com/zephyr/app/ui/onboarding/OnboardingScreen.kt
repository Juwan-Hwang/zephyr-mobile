package com.zephyr.app.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSettingsRow
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ImportSource
import kotlinx.coroutines.launch

/** Two-step onboarding (prototype ob1/ob2): add a subscription, then choose 简单 / 优选. */
@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val c = ZTheme.colors
    var step by remember { mutableIntStateOf(0) }
    var added by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var mode by remember { mutableIntStateOf(1) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().background(c.bg).statusBarsPadding().navigationBarsPadding().padding(top = 24.dp)) {
        ZText("${step + 1} / 2", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
        AnimatedContent(step, transitionSpec = { (slideInHorizontally(ZAnim.slow()) { it / 3 } + fadeIn(ZAnim.standard())) togetherWith (slideOutHorizontally(ZAnim.standard()) { -it / 3 } + fadeOut(ZAnim.micro())) }, label = "ob") { s ->
            Column(Modifier.fillMaxWidth()) {
                if (s == 0) {
                    ZText("添加订阅", Modifier.padding(22.dp), style = ZTheme.type.title)
                    ZSearchField(url, { url = it }, "粘贴链接", Modifier.padding(horizontal = 16.dp), onSubmit = {
                        scope.launch { runCatching { AppGraph.engine.importSubscription(ImportSource.URL, url) }.onSuccess { added = "${it.name}（${it.nodeCount} 个节点）"; step = 1 } }
                    })
                    Spacer(Modifier.height(16.dp))
                    ZListGroup {
                        ZSettingsRow("扫描二维码", chevron = true, onClick = {})
                        ZDivider(); ZSettingsRow("从电脑上的 Zephyr 导入", chevron = true, onClick = {})
                        ZDivider(); ZSettingsRow("从文件导入", chevron = true, onClick = {})
                        ZDivider(); ZSettingsRow("先看看示例", subtitle = "使用演示数据", chevron = true, onClick = { added = "Nebula Cloud（312 个节点）"; step = 1 })
                    }
                    ZText("订阅与流量数据仅保存在此设备上。", Modifier.padding(22.dp), style = ZTheme.type.footnote, color = c.text3)
                } else {
                    ZText("已添加 $added", Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.callout, color = c.connected)
                    ZText("选择使用方式", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.title)
                    Spacer(Modifier.height(16.dp))
                    Choice("简单", "使用订阅提供的分组。节点不可用时自动处理。", mode == 0) { mode = 0 }
                    Spacer(Modifier.height(12.dp))
                    Choice("优选", "每天在 Wi‑Fi 下检测节点。AI 与视频仅使用检测通过的节点。每次约 3 MB。", mode == 1) { mode = 1 }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        if (step == 1) {
            ZButton("继续", { scope.launch { AppGraph.settings.setOnboarded(); onDone() } }, Modifier.fillMaxWidth().padding(horizontal = 16.dp))
            ZText("可随时在设置中更改。", Modifier.fillMaxWidth().padding(12.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3)
        }
    }
}

@Composable
private fun Choice(title: String, body: String, selected: Boolean, onClick: () -> Unit) {
    val c = ZTheme.colors
    Box(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().background(c.surface2, ZTheme.shapes.card)
            .border(if (selected) 2.dp else 1.dp, if (selected) c.accent else c.hairline, ZTheme.shapes.card)
            .zPressable(haptic = true, onClick = onClick).padding(20.dp),
    ) {
        Column {
            ZText(title, style = ZTheme.type.headline)
            Spacer(Modifier.height(6.dp))
            ZText(body, style = ZTheme.type.callout, color = c.text2)
        }
    }
}
