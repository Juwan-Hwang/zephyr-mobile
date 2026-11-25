package com.zephyr.app.ui.home

import com.zephyr.engine.NodeSummary
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import com.zephyr.engine.SceneSource
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Issue #1 (S25 Ultra, debug e244006): with a subscription imported but no connect yet (or a failed one), every scene row
 * read "0 个可用 / 未选择". A row with no exit yet now shows how many nodes the imported profiles hold.
 */
class SceneCountTest {
    private val none = NodeSummary(id = -1, name = "未选择", region = "", protocol = "")
    private val us = NodeSummary(id = 7, name = "🇺🇸 美国 02", region = "US", protocol = "ss")
    private fun scene(sel: NodeSummary, available: Int, source: SceneSource = SceneSource.AUTO) =
        Scene("ai", SceneKind.AI, "AI", available, sel, source = source)

    @Test fun noExitYetShowsProfileNodes() {
        assertEquals(SceneCount.ProfileNodes(128), sceneCount(scene(none, 0), profileNodes = 128))
    }

    @Test fun withAnExitTheTestedCountStays() {
        assertEquals(SceneCount.Available(0), sceneCount(scene(us, 0), 128)) // selected, nothing reachable: honest 0
        assertEquals(SceneCount.Available(4), sceneCount(scene(us, 4), 128))
    }

    @Test fun nothingImportedKeepsZero() {
        assertEquals(SceneCount.Available(0), sceneCount(scene(none, 0), 0))
    }

    @Test fun subscriptionGroupRowsSayGroup() {
        assertEquals(SceneCount.Group, sceneCount(scene(none, 0, SceneSource.SUBSCRIPTION_GROUP), 128))
    }
}
