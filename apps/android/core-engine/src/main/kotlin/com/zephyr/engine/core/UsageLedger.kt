package com.zephyr.engine.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * Today's traffic in 24 hourly buckets plus online time, from mihomo's cumulative counters (same rules as
 * the iOS UsageLedger, contract §14.w): a counter that goes backwards means the core restarted; a new local
 * day starts from zero. Persisted at most every 30 s so a process kill loses little.
 */
class UsageLedger(private val file: File?, private val zone: () -> ZoneId = ZoneId::systemDefault) {
    @Serializable
    data class State(val day: String = "", val hourly: List<Long> = List(24) { 0L }, val onlineMs: Long = 0, val lastTotal: Long = -1, val lastAt: Long = 0)

    private val json = Json { ignoreUnknownKeys = true }
    @Volatile var state: State = file?.takeIf { it.isFile }?.let { runCatching { json.decodeFromString(State.serializer(), it.readText()) }.getOrNull() } ?: State()
        private set
    private var savedAt = 0L

    @Synchronized
    fun record(total: Long, now: Long) {
        val t = Instant.ofEpochMilli(now).atZone(zone())
        val day = t.toLocalDate().toString()
        var s = if (state.day != day) State(day = day, lastTotal = state.lastTotal, lastAt = state.lastAt) else state
        val delta = when {
            s.lastTotal < 0 || total < s.lastTotal -> 0L // first sample or core restarted
            else -> total - s.lastTotal
        }
        val gap = now - s.lastAt
        val online = if (s.lastAt > 0 && gap in 1..10_000) gap else 0L
        val hourly = s.hourly.toMutableList().also { it[t.hour] += delta }
        s = s.copy(hourly = hourly, onlineMs = s.onlineMs + online, lastTotal = total, lastAt = now)
        state = s
        if (now - savedAt >= 30_000) save(now)
    }

    @Synchronized
    fun today(now: Long): State {
        val day = Instant.ofEpochMilli(now).atZone(zone()).toLocalDate().toString()
        return if (state.day == day) state else State(day = day)
    }

    @Synchronized
    fun save(now: Long = System.currentTimeMillis()) {
        val f = file ?: return
        runCatching { f.parentFile?.mkdirs(); val tmp = File(f.path + ".tmp"); tmp.writeText(json.encodeToString(State.serializer(), state)); tmp.renameTo(f) }
        savedAt = now
    }
}
