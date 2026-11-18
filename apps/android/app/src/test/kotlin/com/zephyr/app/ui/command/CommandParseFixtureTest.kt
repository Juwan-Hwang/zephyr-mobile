package com.zephyr.app.ui.command

import com.zephyr.engine.SceneKind
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * contract/fixtures/command-parse-v1.json (§15.b, audit E40/E47): every sample's service / scope / region / action
 * and underlined tokens must match the prototype `parse()` the file was generated from.
 */
class CommandParseFixtureTest {
    private val cases: List<JsonObject> by lazy {
        val dir = System.getProperty("zephyr.fixtures") ?: "../../../contract/fixtures"
        Json.parseToJsonElement(File(dir, "command-parse-v1.json").readText()).jsonObject["cases"]!!.jsonArray.map { it.jsonObject }
    }

    private fun scope(k: SceneKind?) = when (k) {
        SceneKind.AI -> "AI"
        SceneKind.VIDEO -> "视频"
        SceneKind.OTHER -> "其他"
        else -> null
    }

    private fun kind(t: CommandParser.Tok) = when (t) {
        CommandParser.Tok.SERVICE -> "service"
        CommandParser.Tok.REGION -> "region"
        CommandParser.Tok.ACTION -> "action"
    }

    @Test fun matchesSharedSamples() {
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val input = c["input"]!!.jsonPrimitive.content
            val p = CommandParser.parse(input)
            assertEquals("$input service", c["service"]!!.jsonPrimitive.contentOrNull, p.service?.name)
            assertEquals("$input scope", c["scope"]!!.jsonPrimitive.contentOrNull, scope(p.service?.kind))
            val rg = c["region"]?.takeIf { it is JsonObject }?.jsonObject
            assertEquals("$input region", rg?.get("code")?.jsonPrimitive?.content, p.region?.code)
            assertEquals("$input region name", rg?.get("name")?.jsonPrimitive?.content, p.region?.name)
            assertEquals("$input action", c["action"]!!.jsonPrimitive.contentOrNull, p.act?.label)
            val want = c["tokens"]!!.jsonArray.map { t ->
                val o = t.jsonObject
                listOf(o["start"]!!.jsonPrimitive.int, o["len"]!!.jsonPrimitive.int, o["kind"]!!.jsonPrimitive.content, o["text"]!!.jsonPrimitive.content)
            }
            val got = p.spans.map { listOf(it.start, it.length, kind(it.kind), input.substring(it.start, it.start + it.length)) }
            assertEquals("$input tokens", want, got)
        }
    }
}
