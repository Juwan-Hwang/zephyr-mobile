package com.zephyr.engine.core

import com.zephyr.engine.TrafficSample

/**
 * Recent traffic samples the live sampler has read (newest last), for [CoreEngine.recentTraffic].
 *
 * #208 (S25 Ultra, live core): `recentTraffic` used to return nothing with the real core, so every new collection of
 * the home curve (first connect, back from another page, screen on again after 5 s) started from an empty ring and
 * the curve sat at its start. The VPN service samples `traffic()` the whole time the tunnel runs, so keeping what it
 * read lets the home screen open on the last [capacity] seconds instead.
 *
 * Two collectors (service + home) poll at the same 1 Hz: a sample in the same second as the newest one replaces it.
 */
class TrafficHistory(private val capacity: Int = 300) {
    private val ring = ArrayDeque<TrafficSample>(capacity)

    @Synchronized
    fun record(s: TrafficSample) {
        val last = ring.lastOrNull()
        if (last != null && s.at / 1_000 == last.at / 1_000) { ring.removeLast(); ring.addLast(s); return }
        if (last != null && s.at < last.at) ring.clear() // clock went back: drop what no longer lines up
        if (ring.size == capacity) ring.removeFirst()
        ring.addLast(s)
    }

    /** Samples from the last [seconds] seconds before [now], oldest first; at most [seconds] of them. */
    @Synchronized
    fun recent(seconds: Int, now: Long): List<TrafficSample> {
        if (seconds <= 0) return emptyList()
        val from = now - seconds * 1_000L
        return ring.filter { it.at in (from + 1)..now }.takeLast(seconds)
    }

    @Synchronized
    fun clear() = ring.clear()
}
