package com.zephyr.app.ui.home

import com.zephyr.engine.GroupType
import com.zephyr.engine.PolicyGroup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** #208: which group Home's 「节点」 row controls. */
class MainGroupTest {
    private fun g(name: String, type: GroupType = GroupType.SELECT, sel: String? = null) = PolicyGroup(name, type, sel, 3)

    private val groups = listOf(
        g("Zephyr·AI", sel = "US 01"),
        g("自动选择", GroupType.URL_TEST, "HK 02"),
        g("节点选择", sel = "自动选择"),
        g("流媒体", sel = "SG 01"),
        g("GLOBAL", sel = "DIRECT"),
        g("香港", sel = "HK 01"),
    )

    @Test fun matchTargetWinsWhenItIsASelectGroup() {
        assertEquals("流媒体", MainGroup.main(groups, "流媒体")?.name)
        assertEquals(listOf("流媒体", "节点选择", "香港"), MainGroup.selectGroups(groups, "流媒体").map { it.name })
    }

    @Test fun otherwiseTheFirstSelectGroupSkippingSceneGroupsAndGlobal() {
        assertEquals("节点选择", MainGroup.main(groups, null)?.name)
        assertEquals("节点选择", MainGroup.main(groups, "DIRECT")?.name)
        // MATCH → a url-test group: it picks its own node, so the row controls the first select group instead.
        assertEquals("节点选择", MainGroup.main(groups, "自动选择")?.name)
        assertEquals("节点选择", MainGroup.main(groups, "Zephyr·AI")?.name)
    }

    @Test fun noSelectGroupsMeansNoMainGroup() {
        assertNull(MainGroup.main(listOf(g("自动选择", GroupType.URL_TEST, "HK 02")), null))
        assertNull(MainGroup.main(emptyList(), "节点选择"))
    }

    @Test fun nestedChoiceShowsGroupAndLeaf() {
        val main = MainGroup.main(groups, null)!!
        val chain = MainGroup.chain(main, groups)
        assertEquals(listOf("自动选择", "HK 02"), chain)
        assertEquals("自动选择 › HK 02", MainGroup.label(chain))
    }

    @Test fun directChoiceShowsTheNode() {
        val chain = MainGroup.chain(MainGroup.main(groups, "流媒体")!!, groups)
        assertEquals("SG 01", MainGroup.label(chain))
        assertNull(MainGroup.label(MainGroup.chain(g("空", sel = null), groups)))
    }

    @Test fun loopsStop() {
        val loop = listOf(g("A", sel = "B"), g("B", sel = "A"))
        assertEquals(listOf("B", "A"), MainGroup.chain(loop[0], loop))
    }
}
