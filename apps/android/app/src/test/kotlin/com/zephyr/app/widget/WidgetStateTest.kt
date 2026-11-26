package com.zephyr.app.widget

import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.GroupType
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.PolicyGroup
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene
import com.zephyr.engine.SceneKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Widget fixes (S25 Ultra): what the status widget / tile show for a given engine + service state. */
class WidgetStateTest {
    private val none = NodeSummary(id = -1, name = "未选择", region = "", protocol = "")
    private fun scene(id: String, kind: SceneKind, name: String, sel: NodeSummary = none) = Scene(id, kind, name, available = 0, selected = sel)
    private val ai = scene("ai", SceneKind.AI, "AI")
    private val video = scene("video", SceneKind.VIDEO, "视频")
    private val other = scene("other", SceneKind.OTHER, "其他")
    private fun g(name: String, selected: String?) = PolicyGroup(name, GroupType.SELECT, selected, memberCount = 2)

    @Test fun staleConnectedWithoutServiceIsDisconnected() {
        assertEquals(ConnectionStatus.DISCONNECTED, WidgetState.effectiveStatus(ConnectionStatus.CONNECTED, serviceRunning = false))
        assertEquals(ConnectionStatus.DISCONNECTED, WidgetState.effectiveStatus(ConnectionStatus.CONNECTING, serviceRunning = false))
        assertEquals(ConnectionStatus.CONNECTED, WidgetState.effectiveStatus(ConnectionStatus.CONNECTED, serviceRunning = true))
        assertEquals(ConnectionStatus.CONNECTING, WidgetState.effectiveStatus(ConnectionStatus.CONNECTING, serviceRunning = true))
        assertEquals(ConnectionStatus.FAILED, WidgetState.effectiveStatus(ConnectionStatus.FAILED, serviceRunning = false))
        assertEquals(ConnectionStatus.DISCONNECTED, WidgetState.effectiveStatus(ConnectionStatus.DISCONNECTED, serviceRunning = true))
    }

    @Test fun unknownExitsAreLeftOutNotShownAsUnselected() {
        assertTrue(WidgetState.sceneExits(listOf(ai, video, other), emptyList()).isEmpty())
    }

    @Test fun coreChoiceWinsElseLiveSceneGroup() {
        val hk = NodeSummary(id = 7, name = "香港 01", region = "HK", protocol = "TROJAN")
        val groups = listOf(g("Zephyr·视频", "节点选择"), g("节点选择", "美国 02"), g("Zephyr·AI", "日本 03"))
        val out = WidgetState.sceneExits(listOf(ai.copy(selected = hk), video, other), groups)
        assertEquals(listOf("ai", "video"), out.map { it.id })
        assertEquals("香港 01", out[0].selected.name)
        // Group → group → node, region read from the name.
        assertEquals("美国 02", out[1].selected.name)
        assertEquals("US", out[1].selected.region)
    }

    @Test fun leafStopsAtBuiltinsCyclesAndEmptyGroups() {
        assertNull(WidgetState.leaf(listOf(g("A", "DIRECT")), "A"))
        assertNull(WidgetState.leaf(listOf(g("A", "B"), g("B", "A")), "A"))
        assertNull(WidgetState.leaf(listOf(g("A", null)), "A"))
        assertNull(WidgetState.leaf(emptyList(), "A"))
        assertEquals("n1", WidgetState.leaf(listOf(g("A", "B"), g("B", "n1")), "A"))
    }

    @Test fun ruleExitPrefersOtherSceneThenSubscriptionGroup() {
        val jp = NodeSummary(id = 3, name = "日本 01", region = "JP", protocol = "VMESS")
        assertEquals("日本 01", WidgetState.ruleExit(listOf(other.copy(selected = jp)), emptyList()))
        val groups = listOf(g("GLOBAL", "Zephyr·AI"), g("Zephyr·AI", "x"), g("节点选择", "新加坡 02"))
        assertEquals("新加坡 02", WidgetState.ruleExit(emptyList(), groups))
        assertNull(WidgetState.ruleExit(emptyList(), emptyList()))
    }

    @Test fun exitByMode() {
        assertEquals("G", WidgetState.exitFor(ProxyMode.GLOBAL, "G", emptyList(), emptyList()))
        assertNull(WidgetState.exitFor(ProxyMode.DIRECT, "G", emptyList(), emptyList()))
        assertNull(WidgetState.exitFor(ProxyMode.RULE, "G", emptyList(), emptyList()))
    }

    @Test fun everyRefreshBumpsTheTick() {
        val before = WidgetRefresh.tick.value
        WidgetRefresh.bump(); WidgetRefresh.bump()
        assertEquals(before + 2, WidgetRefresh.tick.value)
    }
}
