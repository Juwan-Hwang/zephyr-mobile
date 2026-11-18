package com.zephyr.engine

import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** contract/fixtures/import-payload-v1.json (§15.a): the Kotlin twin and MockEngine must agree with core case by case. */
class ImportPayloadFixtureTest {
    private val cases: List<JsonObject> by lazy {
        val dir = System.getProperty("zephyr.fixtures") ?: "../../../contract/fixtures"
        Json.parseToJsonElement(File(dir, "import-payload-v1.json").readText()).jsonObject["cases"]!!.jsonArray.map { it.jsonObject }
    }

    private fun kindWire(k: ImportPayloadKind) = when (k) {
        ImportPayloadKind.ZEPHYR -> "zephyr"
        ImportPayloadKind.CLASH_INSTALL -> "clashInstall"
        ImportPayloadKind.URL -> "url"
    }

    @Test fun parserMatchesSharedSamples() {
        assertTrue(cases.size >= 17)
        for (c in cases) {
            val id = c["id"]!!.jsonPrimitive.content
            val input = c["input"]!!.jsonPrimitive.content
            val ok = c["ok"]?.jsonObject
            if (ok != null) {
                val got = try { ImportPayloads.parse(input) } catch (e: ImportPayloadException) { fail("$id: ${e.category} ${e.message}"); return }
                assertEquals(id, ok["kind"]!!.jsonPrimitive.content, kindWire(got.kind))
                val want = ok["items"]!!.jsonArray.map { it.jsonObject }
                assertEquals(id, want.size, got.items.size)
                want.zip(got.items).forEach { (w, g) ->
                    assertEquals(id, w["name"]!!.jsonPrimitive.contentOrNull, g.name)
                    assertEquals(id, w["url"]!!.jsonPrimitive.content, g.url)
                    assertEquals(id, w["autoUpdateHours"]!!.jsonPrimitive.intOrNull, g.autoUpdateHours)
                }
            } else {
                val err = c["err"]!!.jsonPrimitive.content
                try { ImportPayloads.parse(input); fail("$id: expected $err") } catch (e: ImportPayloadException) {
                    assertEquals(id, err, e.category.wire)
                }
            }
        }
    }

    @Test fun versionTooNewIsFlagged() {
        val e = runCatching { ImportPayloads.parse(cases.first { it["id"]!!.jsonPrimitive.content == "future-version" }["input"]!!.jsonPrimitive.content) }.exceptionOrNull()
        assertTrue((e as ImportPayloadException).versionTooNew)
    }

    /** Contract §15: MockEngine runs qr / clipboard through the same rules (accepts 1–4, rejects the rest). */
    @Test fun mockQrImportFollowsSamples() = runBlocking {
        for (c in cases) {
            val id = c["id"]!!.jsonPrimitive.content
            val input = c["input"]!!.jsonPrimitive.content
            val engine = MockEngine(latencyScale = 0.0)
            val before = engine.subscriptions().first().size
            val r = runCatching { engine.importSubscription(ImportSource.QR, input) }
            if (c["ok"] != null) {
                assertTrue("$id: ${r.exceptionOrNull()}", r.isSuccess)
                val items = c["ok"]!!.jsonObject["items"]!!.jsonArray
                assertEquals(id, before + items.size, engine.subscriptions().first().size)
                items.first().jsonObject["name"]!!.jsonPrimitive.contentOrNull?.let { assertEquals(id, it, r.getOrThrow().name) }
            } else {
                assertEquals(id, ErrorCode.SUBSCRIPTION_INVALID, (r.exceptionOrNull() as ZephyrException).code)
            }
        }
    }
}
