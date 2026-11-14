package com.zephyr.app.ui.settings

import com.zephyr.engine.LogLevel
import com.zephyr.engine.LogLine
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.TimeZone

/**
 * 设置 › 诊断 › 日志 (iOS parity, PR #97): subscribes to engine.logs(minLevel), keeps the newest [CAPACITY] lines.
 * Changing the level re-subscribes and starts over; pause only stops appending; export is plain text with no
 * credentials (the core redacts its log lines).
 */
class LogsModel(private val engine: ZephyrEngine, private val scope: CoroutineScope) {
    private val _lines = MutableStateFlow<List<LogLine>>(emptyList())
    val lines: StateFlow<List<LogLine>> = _lines.asStateFlow()
    private val _paused = MutableStateFlow(false)
    val paused: StateFlow<Boolean> = _paused.asStateFlow()
    private val _level = MutableStateFlow(LogLevel.INFO)
    val level: StateFlow<LogLevel> = _level.asStateFlow()
    private var job: Job? = null

    fun start() { if (job == null) subscribe() }
    fun stop() { job?.cancel(); job = null }
    fun clear() { _lines.value = emptyList() }
    fun togglePause() { _paused.update { !it } }

    fun setLevel(l: LogLevel) {
        if (l == _level.value) return
        _level.value = l
        if (job != null) subscribe()
    }

    fun append(line: LogLine) {
        if (_paused.value) return
        _lines.update { (it + line).takeLast(CAPACITY) }
    }

    private fun subscribe() {
        job?.cancel()
        _lines.value = emptyList()
        val l = _level.value
        job = scope.launch { engine.logs(l).collect { append(it) } }
    }

    fun exportText(tz: TimeZone = TimeZone.getDefault()): String = _lines.value.joinToString("\n") { format(it, tz) }

    companion object {
        const val CAPACITY = 500

        /** "HH:mm:ss.SSS W message". */
        fun format(line: LogLine, tz: TimeZone = TimeZone.getDefault()): String = "${time(line.at, tz)} ${badge(line.level)} ${line.message}"

        fun time(ms: Long, tz: TimeZone = TimeZone.getDefault()): String {
            val c = Calendar.getInstance(tz).apply { timeInMillis = ms }
            return "%02d:%02d:%02d.%03d".format(c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), c.get(Calendar.SECOND), c.get(Calendar.MILLISECOND))
        }

        fun badge(l: LogLevel): String = when (l) {
            LogLevel.DEBUG -> "D"
            LogLevel.INFO -> "I"
            LogLevel.WARNING -> "W"
            LogLevel.ERROR -> "E"
        }
    }
}
