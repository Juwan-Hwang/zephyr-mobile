package com.zephyr.engine.core

import com.zephyr.engine.Scene

/**
 * Which scenes' results went stale (audit E28; iOS `SceneRetestPlanner`, same rules). Pure, unit-tested.
 * A scene is due when it was never tested or its `testedAt` is at least the latency TTL (设置 › 结果保留) old.
 * A failed retest leaves `testedAt` unchanged, so each scene waits [MIN_RETRY_MS] between automatic attempts.
 */
object SceneRetestPlanner {
    const val MIN_RETRY_MS: Long = 30 * 60 * 1000L
    const val FALLBACK_TTL_HOURS: Int = 24

    fun due(scenes: List<Scene>, ttlHours: Int, connected: Boolean, now: Long, lastAttempt: Map<String, Long> = emptyMap()): List<String> {
        if (!connected) return emptyList()
        val ttl = (if (ttlHours > 0) ttlHours else FALLBACK_TTL_HOURS) * 3_600_000L
        return scenes.mapNotNull { s ->
            val last = lastAttempt[s.id]
            when {
                last != null && now - last < MIN_RETRY_MS -> null
                s.testedAt == null -> s.id
                now - s.testedAt >= ttl -> s.id
                else -> null
            }
        }
    }
}
