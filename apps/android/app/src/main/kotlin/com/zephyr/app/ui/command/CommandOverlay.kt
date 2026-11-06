package com.zephyr.app.ui.command

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.CommandKind
import com.zephyr.engine.CommandSuggestion
import kotlinx.coroutines.delay

/** "搜索或输入指令" (prototype `cmdv`): natural phrases like "Gemini 走日本" become one actionable card. */
@Composable
fun BoxScope.CommandOverlay(visible: Boolean, onDismiss: () -> Unit, onRun: (CommandSuggestion) -> Unit) {
    val c = ZTheme.colors
    var input by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    val suggestions by produceState(emptyList<CommandSuggestion>(), input, visible) {
        if (!visible) return@produceState
        delay(40)
        value = AppGraph.engine.commandSuggestions(input)
    }
    AnimatedVisibility(visible, enter = fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.standard())) {
        Box(Modifier.fillMaxSize().background(c.bg.copy(alpha = 0.86f)).zPressable(label = "关闭", onClick = onDismiss))
    }
    AnimatedVisibility(visible, enter = slideInVertically(ZAnim.slow()) { -it / 6 } + fadeIn(ZAnim.standard()), exit = fadeOut(ZAnim.micro())) {
        BackHandler(visible) { onDismiss() }
        LaunchedEffect(Unit) { input = ""; delay(120); runCatching { focus.requestFocus() } }
        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(horizontal = 16.dp).verticalScroll(rememberScrollState())) {
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                ZSearchField(input, { input = it }, "试试“Gemini 走日本”或 netflix.com", Modifier.weight(1f), focusRequester = focus,
                    onSubmit = { suggestions.firstOrNull()?.let(onRun) })
                Spacer(Modifier.width(8.dp))
                ZText("取消", Modifier.zPressable(onClick = onDismiss).padding(8.dp), style = ZTheme.type.body, color = c.accent)
            }
            Spacer(Modifier.height(18.dp))
            val primary = suggestions.firstOrNull { it.kind == CommandKind.SWITCH_NODE }
            if (primary != null) {
                Tokens(input)
                Spacer(Modifier.height(12.dp))
                ZCard(padding = 20.dp) {
                    ZText(primary.title, style = ZTheme.type.title.copy(fontSize = ZTheme.type.headline.fontSize * 1.25f, fontWeight = ZTheme.type.body.fontWeight))
                    primary.subtitle?.let { Spacer(Modifier.height(4.dp)); ZText(it, style = ZTheme.type.callout, color = c.text3) }
                    Spacer(Modifier.height(18.dp))
                    ZButton("应用", { onRun(primary) }, Modifier.fillMaxWidth())
                }
                Spacer(Modifier.height(16.dp))
            }
            ZText(if (input.isBlank()) "建议" else "指令", Modifier.padding(start = 6.dp, bottom = 8.dp), style = ZTheme.type.footnote, color = c.text3)
            suggestions.filter { it !== primary }.forEach { s ->
                Row(
                    Modifier.fillMaxWidth().zPressable(onClick = { onRun(s) }).padding(horizontal = 6.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ZIcon(iconFor(s.kind), tint = c.text2, size = 20.dp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        ZText(s.title, style = ZTheme.type.body, maxLines = 1)
                        s.subtitle?.let { ZText(it, style = ZTheme.type.footnote, color = c.text3, maxLines = 1) }
                    }
                    ZIcon(ZIcons.ArrowRight, tint = c.text4, size = 16.dp)
                }
            }
        }
    }
}

@Composable
private fun Tokens(input: String) {
    val parts = input.trim().split(Regex("\\s+|走|用")).filter { it.isNotBlank() }
    if (parts.isEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        parts.take(3).forEachIndexed { i, p ->
            ZSurface(shape = ZTheme.shapes.surface) {
                Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                    ZText(listOf("服务", "地区", "范围")[i], style = ZTheme.type.caption, color = ZTheme.colors.text3)
                    ZText(p, style = ZTheme.type.body)
                }
            }
        }
    }
}

private fun iconFor(k: CommandKind) = when (k) {
    CommandKind.TEST_RULE -> ZIcons.Globe
    CommandKind.OPEN_NODE_QUERY -> ZIcons.Search
    CommandKind.SWITCH_MODE -> ZIcons.Filter
    CommandKind.SWITCH_NODE -> ZIcons.ArrowRight
    CommandKind.TOGGLE_CONNECTION -> ZIcons.Bolt
    CommandKind.OPEN_PAGE -> ZIcons.Grid
}
