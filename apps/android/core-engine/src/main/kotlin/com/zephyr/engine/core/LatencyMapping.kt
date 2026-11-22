package com.zephyr.engine.core

/**
 * Contract §0 rule 4 / §15.c / §18.b (A on issue #1, 2026-11-22): the one core → platform latency mapping.
 * `null` (no sample / stale) = untested; any negative = -1 = timeout (`state.timeout`); `>= 0` = the raw value,
 * so 0 ms is a valid (reachable) sample. Never `takeIf { it > 0 }`: that hid timeouts and 0 ms as untested.
 */
object LatencyMapping {
    const val TIMEOUT = -1

    fun map(ms: Int?): Int? = ms?.let { if (it < 0) TIMEOUT else it }

    /** §15.c `reachable` = ms ≥ 0; also the filter for "fastest node" style picks (timeouts excluded). */
    fun reachable(ms: Int?): Boolean = ms != null && ms >= 0
}
