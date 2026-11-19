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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.design.components.ZSegmented
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.LogLevel
import com.zephyr.engine.LogLine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private val levels = listOf(
    LogLevel.DEBUG to R.string.logs_level_debug, LogLevel.INFO to R.string.logs_level_info,
    LogLevel.WARNING to R.string.logs_level_warning, LogLevel.ERROR to R.string.logs_level_error,
)
private val levelNames = levels.toMap()

@Composable
fun LogsScreen(onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val model = remember { LogsModel(AppGraph.engine, scope, AppGraph.appScope) }
    DisposableEffect(model) { model.start(); onDispose { model.stop() } }
    val lines by model.lines.collectAsState()
    val paused by model.paused.collectAsState()
    val level by model.level.collectAsState()
    val c = ZTheme.colors
    val ctx = LocalContext.current

    PageScaffold(BackTo.SETTINGS, stringResource(R.string.logs_title), onBack, trailing = {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            ToolbarText(stringResource(if (paused) R.string.logs_resume else R.string.logs_pause), enabled = true) { model.togglePause() }
            ToolbarText(stringResource(R.string.logs_clear), enabled = lines.isNotEmpty()) { model.clear() }
            ToolbarText(stringResource(R.string.common_share), enabled = lines.isNotEmpty()) {
                scope.launch {
                    // §16.c: 共享诊断数据 only decides whether a summary goes in front of the exported log.
                    val s = AppGraph.engine.settings().first()
                    val diag = if (s.shareDiagnostics) LogsModel.diagnosticsSummary(
                        "${com.zephyr.app.BuildConfig.VERSION_NAME} (${com.zephyr.app.BuildConfig.VERSION_CODE})",
                        "Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})",
                        s, com.zephyr.engine.RecentErrors.snapshot(),
                    ) else null
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, model.exportText(diagnostics = diag))
                    ctx.startActivity(Intent.createChooser(send, null))
                }
            }
        }
    }) {
        ZSegmented(
            levels.map { stringResource(it.second) }, levels.indexOfFirst { it.first == level }, { i -> model.setLevel(levels[i].first) },
            Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        if (lines.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                ZText(stringResource(R.string.logs_empty), style = ZTheme.type.body, color = c.text3)
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
    val a11y = stringResource(R.string.logs_line_a11y, time, levelNames[line.level]?.let { stringResource(it) } ?: "", line.message)
    Row(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = a11y },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ZText(time, style = mono, color = c.text3)
        ZText(LogsModel.badge(line.level), style = mono.copy(fontWeight = FontWeight.Medium), color = tint)
        ZText(line.message, Modifier.weight(1f), style = mono, color = c.text1)
    }
}
