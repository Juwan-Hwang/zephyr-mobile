package com.zephyr.engine.mock

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Contract §18.a: NodeIndex.reachableCount from one nodeFunnel over the mock latency table, filtered by maxAge. */
class MockReachableTest {
    @Test fun reachableComesFromTheSameFunnel() = runTest {
        val e = MockEngine(clock = { 1_700_000_000_000L })
        val idx = e.nodeIndex()
        val f = e.nodeFunnel(24 * 3_600_000L, 200)
        assertNotNull(idx.reachableCount)
        assertEquals(f.reachable, idx.reachableCount)
        assertEquals(f.tested, idx.funnelTested)
        assertTrue(idx.reachableCount!! <= idx.funnelTested!!)
        assertTrue(idx.funnelTested!! > 0)
    }

    @Test fun expiredSamplesAreNotCounted() = runTest {
        var now = 1_700_000_000_000L
        val e = MockEngine(clock = { now })
        assertTrue(e.nodeFunnel(3_600_000L, 200).tested > 0)
        now += 2 * 3_600_000L // fixture samples are 2 h old now
        val f = e.nodeFunnel(3_600_000L, 200)
        assertEquals(0L, f.tested)
        assertEquals(0L, f.reachable)
        // No expiry window: everything in the table counts again.
        assertTrue(e.nodeFunnel(0L, 200).tested > 0)
    }

    @Test fun thresholdDoesNotChangeReachable() = runTest {
        val e = MockEngine(clock = { 1_700_000_000_000L })
        assertEquals(e.nodeFunnel(86_400_000L, 100).reachable, e.nodeFunnel(86_400_000L, 400).reachable)
    }
}
