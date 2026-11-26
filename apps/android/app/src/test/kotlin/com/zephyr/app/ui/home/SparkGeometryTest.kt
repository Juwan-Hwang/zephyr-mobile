package com.zephyr.app.ui.home

import com.zephyr.design.components.SparkGeometry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * #208: with the live core the curve starts from a few samples. They used to be spread edge to edge (step = width/(n-1)),
 * so the curve began at the left and each new sample shoved it around; now they keep the ring's spacing at the right edge.
 */
class SparkGeometryTest {
    private val w = 890f

    @Test fun fewSamplesSitAtTheRightEdge() {
        val xs = SparkGeometry.xs(3, 90, w)
        assertEquals(10f, SparkGeometry.step(3, 90, w), 1e-4f)
        assertArrayEquals(floatArrayOf(870f, 880f, 890f), xs, 1e-3f)
    }

    @Test fun newestIsAlwaysAtTheRightEdge() {
        for (n in 2..90) assertEquals(w, SparkGeometry.xs(n, 90, w).last(), 1e-3f)
    }

    @Test fun fullRingSpansTheWidthLikeBefore() {
        val xs = SparkGeometry.xs(90, 90, w)
        assertEquals(0f, xs.first(), 1e-3f)
        assertEquals(w / 89, xs[1], 1e-3f)
    }

    @Test fun noCapacityKeepsTheOldEdgeToEdgeLayout() {
        assertArrayEquals(floatArrayOf(0f, 445f, 890f), SparkGeometry.xs(3, 0, w), 1e-3f)
    }
}
