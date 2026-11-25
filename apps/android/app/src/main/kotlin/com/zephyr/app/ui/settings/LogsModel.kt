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
class LogsModel(
    private val engine: ZephyrEngine,
    private val scope: CoroutineScope,
    /** Outlives the page, so leaving it can still put mihomo back to info (§16.h). */
    private val bg: CoroutineScope = scope,
) {
    private val _lines = MutableStateFlow<List<LogLine>>(emptyList())
    val lines: StateFlow<List<LogLine>> = _lines.asStateFlow()
    private val _paused = MutableStateFlow(false)
    val paused: StateFlow<Boolean> = _paused.asStateFlow()
    private val _level = MutableStateFlow(LogLevel.INFO)
    val level: StateFlow<LogLevel> = _level.asStateFlow()
    private var job: Job? = null

    fun start() { if (job == null) subscribe() }

    /** Leaving the page: §16.h puts mihomo back to info if the debug segment raised it. */
    fun stop() {
        job?.cancel(); job = null
        if (_level.value == LogLevel.DEBUG) bg.launch { runCatching { engine.setLogLevel(LogLevel.INFO) } }
    }
    fun clear() { _lines.value = emptyList() }
    fun togglePause() { _paused.update { !it } }

    /**
     * Contract §16.h: the debug segment raises mihomo to debug (its ring buffer filters by the current level);
     * leaving it goes back to info. warning / error only filter the display, so info history survives.
     */
    fun setLevel(l: LogLevel) {
        if (l == _level.value) return
        val was = _level.value
        _level.value = l
        if (l == LogLevel.DEBUG) bg.launch { runCatching { engine.setLogLevel(LogLevel.DEBUG) } }
        else if (was == LogLevel.DEBUG) bg.launch { runCatching { engine.setLogLevel(LogLevel.INFO) } }
        if (job != null) subscribe()
    }

    fun append(line: LogLine) {
        if (_paused.value) return
        _lines.update { insertByTime(it, line).takeLast(CAPACITY) }
    }

    private fun subscribe() {
        job?.cancel()
        _lines.value = emptyList()
        val l = _level.value
        job = scope.launch { engine.logs(l).collect { append(it) } }
    }

    /** Plain log text; with [diagnostics] (设置 › 共享诊断数据 on, §16.c) the summary goes first. */
    fun exportText(tz: TimeZone = TimeZone.getDefault(), diagnostics: String? = null): String {
        val log = _lines.value.joinToString("\n") { format(it, tz) }
        return if (diagnostics == null) log else diagnostics + "\n\n" + log
    }

    companion object {
        const val CAPACITY = 500

        private val summaryJson = kotlinx.serialization.json.Json { encodeDefaults = true }

        /**
         * Contract §16.c shareDiagnostics summary: app version, OS version, this section's settings except
         * `trustedWifi` (and the Android-only excludedApps list), and the last 20 error codes with their time.
         */
        fun diagnosticsSummary(
            appVersion: String, os: String, settings: com.zephyr.engine.Settings,
            errors: List<com.zephyr.engine.RecentErrors.Entry>, tz: TimeZone = TimeZone.getDefault(),
        ): String {
            val o = summaryJson.encodeToJsonElement(com.zephyr.engine.Settings.serializer(), settings) as kotlinx.serialization.json.JsonObject
            val tun = (o["tun"] as? kotlinx.serialization.json.JsonObject)?.let { kotlinx.serialization.json.JsonObject(it - "excludedApps") }
            val shown = kotlinx.serialization.json.JsonObject((o - "trustedWifi" - "shareAnonymousPattern").let { if (tun != null) it + ("tun" to tun) else it })
            return buildString {
                append("# Zephyr diagnostics\n")
                append("app: ").append(appVersion).append('\n')
                append("os: ").append(os).append('\n')
                append("settings: ").append(shown.toString()).append('\n')
                append("errors:")
                if (errors.isEmpty()) append(" none")
                errors.takeLast(com.zephyr.engine.RecentErrors.CAPACITY).forEach { e ->
                    val c = Calendar.getInstance(tz).apply { timeInMillis = e.at }
                    append("\n  ").append("%04d-%02d-%02d ".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH)))
                        .append(time(e.at, tz)).append(' ').append(e.code.name.lowercase())
                }
            }
        }

        /**
         * Issue #1 (S25 Ultra log): app lines (written when they happen) and core lines (pulled from mihomo's ring once a
         * second) arrive out of order, so `00:27:59.875 connect failed` was listed before the core's `.552` lines. Lines are
         * kept in time order: [line] goes after every line at or before its time (equal times keep arrival order).
         */
        fun insertByTime(lines: List<LogLine>, line: LogLine): List<LogLine> {
            if (lines.isEmpty() || lines.last().at <= line.at) return lines + line
            var lo = 0; var hi = lines.size
            while (lo < hi) { val mid = (lo + hi) ushr 1; if (lines[mid].at <= line.at) lo = mid + 1 else hi = mid }
            return ArrayList<LogLine>(lines.size + 1).apply { addAll(lines.subList(0, lo)); add(line); addAll(lines.subList(lo, lines.size)) }
        }

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
