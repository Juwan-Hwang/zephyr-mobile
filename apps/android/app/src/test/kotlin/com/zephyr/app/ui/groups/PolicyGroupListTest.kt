package com.zephyr.app.ui.groups

import com.zephyr.engine.GroupType
import com.zephyr.engine.PolicyGroup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PolicyGroupListTest {
    private fun g(name: String, type: GroupType = GroupType.SELECT) = PolicyGroup(name, type, null, 3)

    @Test fun showsTheSubscriptionsGroupsInOrderWithoutSceneGroups() {
        val live = listOf(g("Zephyr·AI"), g("节点选择"), g("Zephyr·AI·Claude"), g("自动选择", GroupType.URL_TEST), g("GLOBAL"), g("故障转移", GroupType.FALLBACK))
        assertEquals(listOf("节点选择", "自动选择", "故障转移"), PolicyGroupList.visible(live).map { it.name })
    }

    @Test fun onlySelectGroupsTakeAManualChoice() {
        assertTrue(PolicyGroupList.selectable(g("节点选择")))
        listOf(GroupType.URL_TEST, GroupType.FALLBACK, GroupType.LOAD_BALANCE, GroupType.RELAY).forEach { assertFalse(PolicyGroupList.selectable(g("x", it))) }
    }
}
