package com.zephyr.engine.core

import com.zephyr.engine.LogLevel
import com.zephyr.engine.LogLine
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Decoder for mihomo-mobile `zm_logs` output. */
internal object LogsJson {
    @Serializable private data class Line(val seq: Long = 0, val level: String = "info", val msg: String = "", val at: Long = 0)
    @Serializable private data class Page(val seq: Long = 0, val lines: List<Line> = emptyList())
    data class Result(val seq: Long, val lines: List<LogLine>)

    private val json = Json { ignoreUnknownKeys = true }

    fun parse(raw: String): Result = runCatching {
        val p = json.decodeFromString(Page.serializer(), raw)
        Result(p.seq, p.lines.map { LogLine(it.at, level(it.level), it.msg) })
    }.getOrDefault(Result(0, emptyList()))

    private fun level(s: String) = when (s.lowercase()) {
        "debug" -> LogLevel.DEBUG
        "warning", "warn" -> LogLevel.WARNING
        "error", "fatal" -> LogLevel.ERROR
        else -> LogLevel.INFO
    }
}
