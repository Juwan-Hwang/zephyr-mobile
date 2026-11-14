package com.zephyr.app.ui.settings

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.design.components.ZSegmented
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.LogLevel
import com.zephyr.engine.LogLine

private val levels = listOf(LogLevel.DEBUG to "调试", LogLevel.INFO to "信息", LogLevel.WARNING to "警告", LogLevel.ERROR to "错误")
private val levelNames = mapOf(LogLevel.DEBUG to "调试", LogLevel.INFO to "信息", LogLevel.WARNING to "警告", LogLevel.ERROR to "错误")

@Composable
fun LogsScreen(onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val model = remember { LogsModel(AppGraph.engine, scope) }
    DisposableEffect(model) { model.start(); onDispose { model.stop() } }
    val lines by model.lines.collectAsState()
    val paused by model.paused.collectAsState()
    val level by model.level.collectAsState()
    val c = ZTheme.colors
    val ctx = LocalContext.current

    PageScaffold("设置", "日志", onBack, trailing = {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            ToolbarText(if (paused) "继续" else "暂停", enabled = true) { model.togglePause() }
            ToolbarText("清空", enabled = lines.isNotEmpty()) { model.clear() }
            ToolbarText("分享", enabled = lines.isNotEmpty()) {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, model.exportText())
                ctx.startActivity(Intent.createChooser(send, null))
            }
        }
    }) {
        ZSegmented(
            levels.map { it.second }, levels.indexOfFirst { it.first == level }, { i -> model.setLevel(levels[i].first) },
            Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (lines.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                ZText("暂无日志", style = ZTheme.type.body, color = c.text3)
            }
        } else {
            val state = rememberLazyListState()
            LaunchedEffect(lines.size, paused) { if (!paused && lines.isNotEmpty()) state.scrollToItem(lines.size - 1) }
            LazyColumn(
                Modifier.fillMaxSize().navigationBarsPadding(), state = state,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 22.dp, end = 22.dp, top = 4.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(lines, key = { i, _ -> i }) { _, line -> LogRow(line) }
            }
        }
    }
}

@Composable
private fun ToolbarText(label: String, enabled: Boolean, onClick: () -> Unit) {
    val c = ZTheme.colors
    Box(Modifier.then(if (enabled) Modifier.zPressable(label = label, onClick = onClick) else Modifier).padding(horizontal = 8.dp, vertical = 10.dp)) {
        ZText(label, style = ZTheme.type.body, color = if (enabled) c.accent else c.text4)
    }
}

@Composable
private fun LogRow(line: LogLine) {
    val c = ZTheme.colors
    val mono = ZTheme.type.monoSmall
    val tint: Color = when (line.level) {
        LogLevel.DEBUG -> c.text3
        LogLevel.INFO -> c.text2
        LogLevel.WARNING -> c.warning
        LogLevel.ERROR -> c.danger
    }
    val time = LogsModel.time(line.at)
    Row(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "$time ${levelNames[line.level]} ${line.message}" },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ZText(time, style = mono, color = c.text3)
        ZText(LogsModel.badge(line.level), style = mono.copy(fontWeight = FontWeight.Medium), color = tint)
        ZText(line.message, Modifier.weight(1f), style = mono, color = c.text1)
    }
}
