package com.zephyr.engine.mock

import com.zephyr.engine.SceneNodeFilter
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Contract v0.7 §19.a/b: sceneFunnel is scoped to the scene's region + node filter and keeps the funnel order. */
class MockSceneFunnelTest {
    private val day = 86_400_000L

    @Test fun scopedAndMonotonic() = runTest {
        val e = MockEngine(clock = { 1_700_000_000_000L })
        val global = e.nodeFunnel(day, 200)
        for (id in listOf("ai", "video", "other")) {
            val f = e.sceneFunnel(id, day, 200)
            assertNotNull(id, f)
            f!!
            assertEquals(global.sourceCount, f.sourceCount)
            assertEquals(200, f.thresholdMs)
            assertTrue(id, f.underThreshold <= f.reachable && f.reachable <= f.tested && f.tested <= f.poolSize)
        }
        assertTrue(e.sceneFunnel("ai", day, 200)!!.poolSize > 0)
    }

    @Test fun followsNodeFilter() = runTest {
        val e = MockEngine(clock = { 1_700_000_000_000L })
        val all = e.sceneFunnel("video", 0, 200)!!
        runCatching { e.setSceneNodeFilter("video", SceneNodeFilter.UHD) }
        assertTrue(e.sceneFunnel("video", 0, 200)!!.poolSize <= all.poolSize)
    }

    @Test fun unknownSceneIsNull() = runTest {
        assertNull(MockEngine(clock = { 1_700_000_000_000L }).sceneFunnel("nope", 0, 200))
    }
}
