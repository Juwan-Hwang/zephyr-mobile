package com.zephyr.app.ui.home

import com.zephyr.engine.NodeFunnel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** J-1 mini funnel (spec §9.3): log10 widths shrink left to right, fill the width, and a 0 keeps its 2 dp slot. Same cases as iOS MiniFunnelTests. */
class MiniFunnelTest {
    private fun f(pool: Long, tested: Long, ok: Long, under: Long) = NodeFunnel(2, pool, tested, ok, under, 200)

    @Test fun widthsShrinkLeftToRightAndFit() {
        val w = miniFunnelWidths(f(10_000_000, 41_288, 3_120, 9), total = 120f, gap = 2f)
        assertEquals(4, w.size)
        for (i in 1 until w.size) assertTrue(w[i] < w[i - 1])
        assertEquals(120f, w.sum() + 6f, 0.001f)
        assertTrue(w[3] > 2f) // 9 and 10⁷ both visible
    }

    @Test fun zeroCountsKeepMinimum() {
        val w = miniFunnelWidths(f(512, 0, 0, 0), total = 120f, gap = 2f)
        assertEquals(2f, w[1], 0f); assertEquals(2f, w[2], 0f); assertEquals(2f, w[3], 0f)
        assertEquals(listOf(2f, 2f, 2f, 2f), miniFunnelWidths(f(0, 0, 0, 0), total = 120f, gap = 2f))
    }
}
