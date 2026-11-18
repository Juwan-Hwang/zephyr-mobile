package com.zephyr.engine.core

import com.zephyr.engine.NodeSummary
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.SceneSource
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.runBlocking
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Audit E28 (iOS SceneRetestPlannerTests): stale / never-tested scenes, TTL from settings, 30 min back-off. */
class SceneRetestPlannerTest {
    private val node = NodeSummary(1, "n", "JP", protocol = "VLESS")
    private fun scene(id: String, testedAt: Long?) = Scene(id, SceneKind.VIDEO, id, 1, node, null, SceneSource.AUTO, testedAt)
    private val h = 3_600_000L
    private val now = 100 * h

    @Test fun dueWhenNeverTestedOrOlderThanTtl() {
        val list = listOf(scene("fresh", now - 2 * h), scene("stale", now - 6 * h), scene("never", null))
        assertEquals(listOf("stale", "never"), SceneRetestPlanner.due(list, ttlHours = 6, connected = true, now = now))
        assertEquals(listOf("never"), SceneRetestPlanner.due(list, ttlHours = 24, connected = true, now = now))
    }

    @Test fun nothingWhileDisconnected() {
        assertTrue(SceneRetestPlanner.due(listOf(scene("never", null)), 24, connected = false, now = now).isEmpty())
    }

    @Test fun zeroTtlFallsBackTo24h() {
        assertEquals(listOf("old"), SceneRetestPlanner.due(listOf(scene("old", now - 25 * h), scene("new", now - 23 * h)), 0, true, now))
    }

    @Test fun backsOffThirtyMinutesPerScene() {
        val list = listOf(scene("a", null), scene("b", null))
        val tried = mapOf("a" to now - 10 * 60_000L, "b" to now - 31 * 60_000L)
        assertEquals(listOf("b"), SceneRetestPlanner.due(list, 24, true, now, tried))
    }

    /** Contract §15.c mock: prototype lede 2 / 512, counts consistent (tested ≥ reachable ≥ under). */
    @Test fun mockFunnel() = runBlocking {
        val f = MockEngine(clock = { 0L }).nodeFunnel(24 * h, 0)
        assertEquals(2, f.sourceCount); assertEquals(512L, f.poolSize); assertEquals(300, f.thresholdMs)
        assertTrue(f.tested in 1..512 && f.reachable <= f.tested && f.underThreshold <= f.reachable, "$f")
    }
}
