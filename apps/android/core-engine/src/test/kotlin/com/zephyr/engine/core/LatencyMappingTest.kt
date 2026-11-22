package com.zephyr.engine.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Contract §0 rule 4 / §15.c / §18.b as decided by A on issue #1: null = untested, < 0 = -1 timeout, >= 0 raw. */
class LatencyMappingTest {
    @Test fun nullIsUntested() = assertNull(LatencyMapping.map(null))

    @Test fun negativeIsTimeout() {
        assertEquals(-1, LatencyMapping.map(-1))
        assertEquals(-1, LatencyMapping.map(-5000))
        assertEquals(-1, LatencyMapping.map(Int.MIN_VALUE))
    }

    @Test fun zeroAndPositiveAreRaw() {
        assertEquals(0, LatencyMapping.map(0))
        assertEquals(1, LatencyMapping.map(1))
        assertEquals(162, LatencyMapping.map(162))
    }

    @Test fun reachableIsNonNegative() {
        assertTrue(LatencyMapping.reachable(0))
        assertTrue(LatencyMapping.reachable(300))
        assertFalse(LatencyMapping.reachable(-1))
        assertFalse(LatencyMapping.reachable(null))
    }
}
