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
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ImportSource
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import com.zephyr.engine.SceneSource
import com.zephyr.app.ui.subs.ImportOptions
import com.zephyr.app.ui.subs.rememberSubscriptionImporter
import com.zephyr.design.format.ZFormat

/** Two-step onboarding (prototype ob1/ob2): add a subscription, then choose 简单 / 优选. */
@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val c = ZTheme.colors
    var step by remember { mutableIntStateOf(0) }
    var added by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var showField by remember { mutableStateOf(false) }
    var mode by remember { mutableIntStateOf(1) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // Review L-P1-2: same import path as the sheet; failures are shown; the chosen mode is written before finishing.
    val imp = rememberSubscriptionImporter { s -> added = "${s.name}（${ZFormat.grouped(s.nodeCount)} 个节点）"; step = 1 }
    Column(Modifier.fillMaxSize().background(c.bg).statusBarsPadding().navigationBarsPadding().padding(top = 24.dp)) {
        ZText("${step + 1} / 2", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
        AnimatedContent(step, transitionSpec = { (slideInHorizontally(ZAnim.slow()) { it / 3 } + fadeIn(ZAnim.standard())) togetherWith (slideOutHorizontally(ZAnim.standard()) { -it / 3 } + fadeOut(ZAnim.micro())) }, label = "ob") { s ->
            Column(Modifier.fillMaxWidth()) {
                if (s == 0) {
                    ZText("添加订阅", Modifier.padding(22.dp), style = ZTheme.type.title)
                    if (showField) {
                        Column(Modifier.padding(horizontal = 16.dp)) {
                            ZSearchField(url, { url = it; imp.error = null }, "粘贴订阅链接", onSubmit = { imp.submit(ImportSource.URL, url) })
                            Spacer(Modifier.height(12.dp))
                            ZButton(if (imp.busy) "正在添加…" else "添加", { imp.submit(ImportSource.URL, url) }, Modifier.fillMaxWidth(), enabled = url.isNotBlank() && !imp.busy)
                        }
                        Spacer(Modifier.height(16.dp))
                    }
                    ImportOptions(imp, clipboard = false, paste = if (showField) null else ({
                        // Prefill from the clipboard when it holds a link; otherwise open the field to paste by hand.
                        val t = imp.clipboardText().also { imp.error = null }
                        if (t != null && (t.startsWith("https://") || t.startsWith("http://"))) { url = t; imp.submit(ImportSource.CLIPBOARD, t) }
                        showField = true
                    }))
                    if (imp.busy && !showField) ZText("正在添加…", Modifier.padding(horizontal = 22.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.text2)
                    imp.error?.let { ZText(it, Modifier.padding(horizontal = 22.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.danger) }
                    imp.hint?.let { ZText(it, Modifier.padding(horizontal = 22.dp, vertical = 4.dp), style = ZTheme.type.footnote, color = c.text2) }
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
            ZButton("继续", {
                if (!saving) scope.launch {
                    saving = true
                    applyOnboardingMode(simple = mode == 0)
                    AppGraph.settings.setOnboarded(); onDone()
                }
            }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), enabled = !saving)
            ZText("可随时在设置中更改。", Modifier.fillMaxWidth().padding(12.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3)
        }
    }
}

/**
 * 简单 = every scene follows the subscription's own group; 优选 = Zephyr picks from tested nodes.
 * Fresh install: no exit has been used yet, so switching AI here is not an exit change the user must confirm.
 */
private suspend fun applyOnboardingMode(simple: Boolean) {
    val engine = AppGraph.engine
    val source = if (simple) SceneSource.SUBSCRIPTION_GROUP else SceneSource.AUTO
    val scenes = runCatching { withTimeoutOrNull(2_000) { engine.scenes().first() } }.getOrNull().orEmpty()
    scenes.filter { it.source != source }.forEach { runCatching { engine.setSceneSource(it.id, source) } }
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
