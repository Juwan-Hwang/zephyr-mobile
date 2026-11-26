package com.zephyr.engine.core

import com.zephyr.engine.TrafficSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #208 (S25 Ultra, live core): `recentTraffic` returned nothing with the real core, so the home curve restarted from an
 * empty ring on every new collection. The history keeps what the sampler read so the curve reopens on recent seconds.
 */
class TrafficHistoryTest {
    private fun s(sec: Long, down: Long = sec) = TrafficSample(sec * 1_000, 0, down)

    @Test fun keepsWhatTheSamplerRead() {
        val h = TrafficHistory()
        (1L..120L).forEach { h.record(s(it)) }
        val back = h.recent(90, now = 120_000)
        assertEquals(90, back.size)
        assertEquals(31_000L, back.first().at)
        assertEquals(120_000L, back.last().at) // newest last
    }

    @Test fun twoCollectorsInTheSameSecondKeepOneSample() {
        val h = TrafficHistory()
        h.record(TrafficSample(10_100, 0, 1)); h.record(TrafficSample(10_600, 0, 2)); h.record(TrafficSample(11_050, 0, 3))
        val back = h.recent(90, now = 11_100)
        assertEquals(listOf(2L, 3L), back.map { it.downBps })
    }

    @Test fun oldSamplesAreNotShownAsRecent() {
        val h = TrafficHistory()
        (1L..10L).forEach { h.record(s(it)) }
        // Home opened 5 minutes after the last reading (tunnel was down): nothing stale on the curve.
        assertTrue(h.recent(90, now = 310_000).isEmpty())
        assertEquals(listOf(9_000L, 10_000L), h.recent(2, now = 10_000).map { it.at })
    }

    @Test fun capacityAndClear() {
        val h = TrafficHistory(capacity = 5)
        (1L..8L).forEach { h.record(s(it)) }
        assertEquals(listOf(4_000L, 5_000L, 6_000L, 7_000L, 8_000L), h.recent(90, now = 8_000).map { it.at })
        h.clear()
        assertTrue(h.recent(90, now = 8_000).isEmpty())
    }
}
