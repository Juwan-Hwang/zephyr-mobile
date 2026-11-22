package com.zephyr.app.ui.command

import com.zephyr.engine.ProxyMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** J-3 (spec §9.5): fixed group order, 5-row cap, Enter row and hardware-keyboard highlight (mirrors iOS CommandGroupTests). */
class CommandResultsTest {
    private fun rows(vararg t: Pair<String, CommandTarget>) = CommandResults.rows(t.map { Triple(it.first, null, it.second) })

    @Test fun groupsFollowSpecOrderAndDropEmpty() {
        val g = CommandResults.groups(rows(
            "claude.ai" to CommandTarget.Rule("claude.ai"),
            "东京 01" to CommandTarget.Nodes("jp", 1),
            "规则" to CommandTarget.Mode(ProxyMode.RULE),
            "设置" to CommandTarget.Page(CommandPage.SETTINGS),
        ))
        assertEquals(listOf(CommandGroup.COMMAND, CommandGroup.NODE, CommandGroup.SETTINGS, CommandGroup.RULE_TEST), g.map { it.group })
        assertEquals("规则", CommandResults.firstRow(g)?.title)
    }

    @Test fun actionLabels() {
        assertEquals(CommandVerb.APPLY, CommandTarget.Mode(ProxyMode.GLOBAL).verb)
        assertEquals(CommandVerb.APPLY, CommandTarget.Toggle(true).verb)
        assertEquals(CommandVerb.OPEN, CommandTarget.Scene("ai").verb)
        assertEquals(CommandVerb.OPEN, CommandTarget.Nodes("jp", 1).verb)
        assertEquals(CommandVerb.OPEN, CommandTarget.Page(CommandPage.LOGS).verb)
        assertEquals(CommandVerb.TEST, CommandTarget.Rule("x.com").verb)
    }

    @Test fun groupCapsAtFiveUntilExpanded() {
        val r = rows(*Array(7) { "p$it" to CommandTarget.Page(CommandPage.entries[it]) })
        val g = CommandResults.groups(r)
        assertEquals(5, CommandResults.visibleRows(g, emptySet()).size)
        assertEquals(7, CommandResults.visibleRows(g, setOf(CommandGroup.SETTINGS)).size)
    }

    @Test fun duplicateRowsGetUniqueKeys() {
        val r = rows("a" to CommandTarget.Rule("a"), "a" to CommandTarget.Rule("a"))
        assertEquals(2, r.map { it.key }.toSet().size)
    }

    @Test fun matchingIsPrefixForCommandsAndSubstringElsewhere() {
        val disconnect = CommandCandidate("断开连接", null, CommandTarget.Toggle(false), listOf("断开", "disconnect"), prefix = true)
        assertFalse(CommandResults.matches("连接", disconnect))
        assertTrue(CommandResults.matches("断开", disconnect))
        assertTrue(CommandResults.matches("DIS", disconnect))
        assertFalse(CommandResults.matches("d", disconnect))
        assertTrue(CommandResults.matches("直", CommandCandidate("直", null, CommandTarget.Mode(ProxyMode.DIRECT), prefix = true)))
        val page = CommandCandidate("本地代理端口", null, CommandTarget.Page(CommandPage.LOCAL_PROXY))
        assertTrue(CommandResults.matches("代理", page))
        assertFalse(CommandResults.matches("  ", page))
    }

    @Test fun singleCharacterToggleAliasesMatchWholeWordOnly() {
        val connect = CommandCandidate("连接", null, CommandTarget.Toggle(true), CommandResults.CONNECT_ALIASES, prefix = true)
        val disconnect = CommandCandidate("断开连接", null, CommandTarget.Toggle(false), CommandResults.DISCONNECT_ALIASES, prefix = true)
        assertTrue(CommandResults.matches("开", connect))
        assertTrue(CommandResults.matches(" 开 ", connect))
        assertFalse(CommandResults.matches("开", disconnect))
        assertTrue(CommandResults.matches("关", disconnect))
        assertFalse(CommandResults.matches("关", connect))
        assertFalse(CommandResults.matches("开启", connect))
        assertFalse(CommandResults.matches("关于", disconnect))
        // Same as iOS: other words still reach their row; a lone 「开」 never prefix-matches a mode.
        assertTrue(CommandResults.matches("连接", connect))
        assertFalse(CommandResults.matches("开", CommandCandidate("规则", null, CommandTarget.Mode(ProxyMode.RULE), listOf("规则模式", "rule"), prefix = true)))
    }

    @Test fun highlightWithoutPreviewStartsAtSecondRowAndStopsAtEnds() {
        val keys = listOf("a", "b", "c")
        assertEquals("b", CommandResults.moveHighlight(null, keys, 1, hasPrimary = false))
        assertEquals("c", CommandResults.moveHighlight("c", keys, 1, hasPrimary = false))
        assertEquals("a", CommandResults.moveHighlight("a", keys, -1, hasPrimary = false))
        assertEquals("a", CommandResults.moveHighlight(null, keys, -1, hasPrimary = false))
    }

    @Test fun highlightWithPreviewStartsAtFirstRowAndReturnsToPreview() {
        val keys = listOf("a", "b")
        assertEquals("a", CommandResults.moveHighlight(null, keys, 1, hasPrimary = true))
        assertNull(CommandResults.moveHighlight("a", keys, -1, hasPrimary = true))
        assertNull(CommandResults.moveHighlight(null, emptyList(), 1, hasPrimary = true))
    }

    @Test fun enterRunsHighlightElsePreviewElseFirstRow() {
        val g = CommandResults.groups(rows("规则" to CommandTarget.Mode(ProxyMode.RULE), "x.com" to CommandTarget.Rule("x.com")))
        val ruleKey = g.last().rows.single().key
        assertEquals(ruleKey, CommandResults.enterRow(g, emptySet(), ruleKey, hasPrimary = true)?.key)
        assertNull(CommandResults.enterRow(g, emptySet(), null, hasPrimary = true))
        assertEquals("规则", CommandResults.enterRow(g, emptySet(), null, hasPrimary = false)?.title)
        assertEquals("规则", CommandResults.enterRow(g, emptySet(), "gone", hasPrimary = false)?.title)
    }
}
