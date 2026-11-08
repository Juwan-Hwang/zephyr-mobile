package com.zephyr.app.ui.command

import com.zephyr.engine.SceneKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CommandParserTest {
    @Test fun geminiJapan() {
        val p = CommandParser.parse("Gemini 走日本")
        assertEquals("gemini", p.service?.app?.id)
        assertEquals(SceneKind.AI, p.service?.kind)
        assertEquals("JP", p.region?.code)
        assertEquals(listOf(CommandParser.Tok.SERVICE, CommandParser.Tok.REGION), p.spans.map { it.kind })
        assertEquals(0 to 6, p.spans[0].start to p.spans[0].length)
    }

    @Test fun netflixIsVideoNotAi() {
        val p = CommandParser.parse("Netflix 走日本")
        assertEquals(SceneKind.VIDEO, p.service?.kind)
    }

    @Test fun githubDirect() {
        val p = CommandParser.parse("GitHub 直连")
        assertEquals("github.com", p.service?.host)
        assertEquals(CommandParser.Act.DIRECT, p.act)
    }

    @Test fun sceneWord4k() {
        val p = CommandParser.parse("视频只用 4K 节点")
        assertTrue(p.service!!.isSceneWord)
        assertEquals(CommandParser.Act.UHD, p.act)
    }

    @Test fun shortLatinNeedsWordBoundary() {
        assertNull(CommandParser.parse("status").region)
        assertEquals("US", CommandParser.parse("claude us").region?.code)
    }

    @Test fun regionAloneHasNoChips() {
        val p = CommandParser.parse("香港")
        assertEquals("HK", p.region?.code)
        assertTrue(!p.hasChips)
    }
}
