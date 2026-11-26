package com.zephyr.app.ui.home

import com.zephyr.app.R
import com.zephyr.app.ui.common.NodeSort
import com.zephyr.app.ui.common.NodeSortPref
import com.zephyr.app.ui.common.UiText
import com.zephyr.engine.GroupType
import com.zephyr.engine.NodeId
import com.zephyr.engine.NodePage
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.PolicyGroup
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** #208: Home's node row and sheet switch in one tap (rule: selectInGroup; global: setGlobalNode with library ids). */
@OptIn(ExperimentalCoroutinesApi::class)
class NodePickerTest {
    private val main = UnconfinedTestDispatcher()

    @Before fun setUp() { Dispatchers.setMain(main); NodeSortPref.set(NodeSort.DEFAULT) }
    @After fun tearDown() { NodeSortPref.set(NodeSort.DEFAULT); Dispatchers.resetMain() }

    private fun mock() = MockEngine(demo = true, compute = Dispatchers.Unconfined)

    @Test fun ruleModeRowShowsTheMainGroupsChoiceAndOneTapSwitches() = runBlocking {
        val e = mock()
        val vm = HomeViewModel(e)
        main.scheduler.runCurrent()
        val p = vm.picker
        // The mock's final rule goes to a scene, so the main group is the first select group, 节点选择.
        assertEquals("新加坡 02", p.ui.value.label)
        assertEquals(listOf("节点选择", "AI", "流媒体"), p.ui.value.groups)

        p.open(); main.scheduler.runCurrent()
        assertTrue(p.ui.value.open)
        assertEquals("节点选择", p.ui.value.group)
        val target = p.ui.value.rows[3]
        p.pick(target); main.scheduler.runCurrent()

        assertFalse(p.ui.value.open)
        assertEquals(target.name, e.policyGroups().first().first { it.name == "节点选择" }.selected)
        assertEquals(target.name, p.ui.value.label)
        val toast = vm.ui.value.toast!!
        assertEquals(UiText.Res(R.string.home_switched_to, listOf(target.name)), toast.message)
    }

    @Test fun undoPutsThePreviousMemberBack() = runBlocking {
        val e = mock()
        val vm = HomeViewModel(e)
        main.scheduler.runCurrent()
        val p = vm.picker
        p.open(); main.scheduler.runCurrent()
        val first = p.ui.value.rows[0]
        p.pick(first); main.scheduler.runCurrent()
        p.open(); main.scheduler.runCurrent()
        val second = p.ui.value.rows[1]
        p.pick(second); main.scheduler.runCurrent()
        vm.undo(); main.scheduler.runCurrent()
        assertEquals(first.name, e.policyGroups().first().first { it.name == "节点选择" }.selected)
    }

    @Test fun chipsSwitchGroups() = runBlocking {
        val e = mock()
        val vm = HomeViewModel(e)
        main.scheduler.runCurrent()
        val p = vm.picker
        p.open(); main.scheduler.runCurrent()
        p.chooseGroup("流媒体"); main.scheduler.runCurrent()
        val n = p.ui.value.rows[2]
        p.pick(n); main.scheduler.runCurrent()
        val groups = e.policyGroups().first()
        assertEquals(n.name, groups.first { it.name == "流媒体" }.selected)
        assertEquals("新加坡 02", groups.first { it.name == "节点选择" }.selected)
    }

    @Test fun globalModeListsLibraryNodesAndSetsTheGlobalExit() = runBlocking {
        val e = mock()
        val vm = HomeViewModel(e)
        e.setMode(ProxyMode.GLOBAL); main.scheduler.runCurrent()
        val p = vm.picker
        assertEquals(ProxyMode.GLOBAL, p.ui.value.mode)
        assertEquals("东京 03", p.ui.value.label)
        p.open(); main.scheduler.runCurrent()
        assertTrue(p.ui.value.rows.isNotEmpty())
        assertTrue(p.ui.value.rows.all { it.id >= 0 })
        val n = p.ui.value.rows.first { it.name != "东京 03" }
        p.pick(n); main.scheduler.runCurrent()
        assertEquals(n.id, e.connectionState().first().globalNodeId)
        assertEquals(n.name, p.ui.value.label)
        assertEquals(UiText.Res(R.string.home_switched_to, listOf(n.name)), vm.ui.value.toast!!.message)
    }

    @Test fun sortAppliesAndDefaultRestoresTheSubscriptionOrder() = runBlocking {
        val vm = HomeViewModel(mock())
        main.scheduler.runCurrent()
        val p = vm.picker
        p.open(); main.scheduler.runCurrent()
        val raw = p.ui.value.rows
        p.setSort(NodeSort.NAME); main.scheduler.runCurrent()
        assertEquals(raw.map { it.name }.sortedWith(java.text.Collator.getInstance().apply { strength = java.text.Collator.SECONDARY }), p.ui.value.rows.map { it.name })
        p.setSort(NodeSort.DEFAULT); main.scheduler.runCurrent()
        assertEquals(raw, p.ui.value.rows)
    }

    /** Live-core shape: MATCH names a select group, whose choice is itself a group. */
    private class Nested(private val m: MockEngine) : ZephyrEngine by m {
        val groups = MutableStateFlow(listOf(
            PolicyGroup("Zephyr·其他", GroupType.SELECT, "JP 01", 1),
            PolicyGroup("节点选择", GroupType.SELECT, "SG 01", 2),
            PolicyGroup("🚀 代理", GroupType.SELECT, "♻️ 自动", 2),
            PolicyGroup("♻️ 自动", GroupType.URL_TEST, "HK 01", 2),
        ))
        override fun policyGroups(): Flow<List<PolicyGroup>> = groups
        override suspend fun finalPolicy(): String = "🚀 代理"
        override suspend fun groupMembers(group: String, offset: Int, limit: Int): NodePage {
            val rows = when (group) {
                "🚀 代理" -> listOf(NodeSummary(-1, "♻️ 自动", "UN", protocol = "URLTEST"), NodeSummary(-2, "SG 01", "SG", protocol = "VMESS", latencyMs = 80))
                "♻️ 自动" -> listOf(NodeSummary(-3, "HK 01", "HK", protocol = "VMESS", latencyMs = 42), NodeSummary(-4, "HK 02", "HK", protocol = "VMESS", latencyMs = 60))
                else -> emptyList()
            }
            return NodePage(rows, 0, rows.size.toLong())
        }
        var selected: Pair<String, NodeId>? = null
        override suspend fun selectInGroup(group: String, nodeId: NodeId) { selected = group to nodeId }
    }

    @Test fun matchTargetGroupWithNestedChoice() = runBlocking {
        val e = Nested(mock())
        val vm = HomeViewModel(e)
        main.scheduler.runCurrent()
        val p = vm.picker
        assertEquals("♻️ 自动 › HK 01", p.ui.value.label)
        assertEquals(42, p.ui.value.latencyMs)
        assertEquals(listOf("🚀 代理", "节点选择"), p.ui.value.groups)
        p.open(); main.scheduler.runCurrent()
        assertEquals(setOf("♻️ 自动"), p.ui.value.groupNames)
        p.pick(p.ui.value.rows.first { it.name == "SG 01" }); main.scheduler.runCurrent()
        assertEquals("🚀 代理" to -2L, e.selected)
        assertEquals("SG 01", p.ui.value.label)
    }
}
