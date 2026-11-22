package com.zephyr.app.ui.scene

import com.zephyr.engine.NodeSummary
import org.junit.Assert.assertEquals
import org.junit.Test

/** J-6 tick bar (spec §9.6): 0–600 ms linear axis with > 600 at the right end; timeouts counted, not drawn; untested ignored. */
class LatencyTickBarTest {
    private fun n(id: Long, ms: Int?) = NodeSummary(id = id, name = "n$id", region = "JP", protocol = "", latencyMs = ms)

    @Test fun axisIsLinearAndClamped() {
        assertEquals(0.5f, tickX(0, 301f), 0.001f)
        assertEquals(100.5f, tickX(200, 301f), 0.001f)
        assertEquals(300.5f, tickX(600, 301f), 0.001f)
        assertEquals(300.5f, tickX(720, 301f), 0.001f)
        assertEquals(0.5f, tickX(-1, 301f), 0.001f)
    }

    @Test fun statsSplitMeasuredTimeoutsAndUntested() {
        val s = latencyTickStats(listOf(n(1, 38), n(2, 199), n(3, 200), n(4, 720), n(5, -1), n(6, -1), n(7, null)))
        assertEquals(listOf(1L to 38, 2L to 199, 3L to 200, 4L to 720), s.measured)
        assertEquals(2, s.timeouts)
        assertEquals(2, s.underThreshold) // 200 ms itself is "slow" (latency.threshold-slow)
    }
}
