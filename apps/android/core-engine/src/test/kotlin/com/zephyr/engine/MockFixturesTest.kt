package com.zephyr.engine

import com.zephyr.engine.mock.MockCatalog
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** contract/mock-spec.md: the Kotlin MockEngine must match contract/fixtures/mock-v0.json item by item. */
class MockFixturesTest {
    private val fx: JsonObject by lazy {
        val dir = System.getProperty("zephyr.fixtures") ?: "../../../contract/fixtures"
        Json.parseToJsonElement(File(dir, "mock-v0.json").readText()).jsonObject
    }
    private val engine = MockEngine()

    private val JsonElement.s get() = jsonPrimitive.content
    private val JsonElement.l get() = jsonPrimitive.long
    private val JsonElement.i get() = jsonPrimitive.int

    @Test fun totals() {
        assertEquals(fx["total"]!!.l, MockCatalog.TOTAL)
        fx["regions"]!!.jsonArray.forEachIndexed { i, r ->
            val g = MockCatalog.REGIONS[i]
            assertEquals(r.jsonObject["code"]!!.s, g.code)
            assertEquals(r.jsonObject["count"]!!.i, g.count)
            assertEquals(r.jsonObject["baseLatency"]!!.i, g.baseLatency)
            assertEquals(r.jsonObject["cities"]!!.jsonArray.map { it.s }, g.cities.toList())
            assertEquals(r.jsonObject["carriers"]!!.jsonArray.map { it.s }, g.carriers.toList())
        }
    }

    @Test fun nodes() {
        val nodes = fx["nodes"]!!.jsonArray
        assertTrue(nodes.size > 100)
        for (n in nodes) {
            val o = n.jsonObject
            val r = o["region"]!!.i
            val j = o["index"]!!.i
            val s = MockCatalog.summary(r, j)
            assertEquals("id $r/$j", o["id"]!!.l, s.id)
            assertEquals("name $r/$j", o["name"]!!.s, s.name)
            assertEquals("tag $r/$j", o["tag"]!!.s, s.tag)
            assertEquals("protocol $r/$j", o["protocol"]!!.s, s.protocol)
            assertEquals("carrier $r/$j", o["carrier"]!!.s, s.carrier)
            assertEquals("city $r/$j", o["city"]!!.s, s.city)
            o["hash"]?.let { assertEquals("hash $r/$j", it.l, MockCatalog.hsh(r, j)) }
            val cached = o["cachedLatency"]
            val expect = if (cached == null || cached is JsonNull) null else cached.i
            assertEquals("latency $r/$j", expect, s.latencyMs)
        }
    }

    @Test fun queries() = runTest {
        for (q in fx["queries"]!!.jsonArray) {
            val o = q.jsonObject
            val query = o["query"]!!.s
            val res = engine.queryNodes(query)
            assertEquals("total '$query'", o["total"]!!.l, res.total)
            val secs = o["sections"]!!.jsonArray.map { it.jsonObject["region"]!!.s to it.jsonObject["count"]!!.l }
            assertEquals("sections '$query'", secs, res.sections.map { it.region to it.count })
            val first = o["firstRows"]?.jsonArray ?: continue
            // Rebuild the first rows (headers + nodes) from paging.
            val page = engine.nodeRows(res.token, 0, 40).rows
            val got = ArrayList<String>()
            var ord = 0
            for (sec in res.sections) {
                got += "H:" + sec.region
                for (k in 0 until sec.count) { if (got.size >= first.size) break; got += page[ord++].let { "${it.id}:${it.name}" } }
                if (got.size >= first.size) break
            }
            val want = first.map { r ->
                val ro = r.jsonObject
                ro["header"]?.let { "H:" + it.s } ?: "${ro["id"]!!.l}:${ro["name"]!!.s}"
            }
            assertEquals("rows '$query'", want, got.take(want.size))
        }
    }

    @Test fun rules() = runTest {
        val rules = fx["rules"]!!.jsonObject
        assertEquals(rules["total"]!!.l, engine.ruleStats().total)
        for (t in rules["tests"]!!.jsonArray) {
            val o = t.jsonObject
            val trace = engine.testRule(o["input"]!!.s)
            val li = o["layerIndex"]
            assertEquals("layer ${o["input"]}", if (li == null || li is JsonNull) null else li.i, trace.layerIndex)
            assertEquals("rule ${o["input"]}", o["rule"]!!.s, trace.rule)
            val rn = o["ruleNo"]
            assertEquals("ruleNo ${o["input"]}", if (rn == null || rn is JsonNull) null else rn.l, trace.ruleNo)
            val policy = o["policy"]!!.s
            val mapped = when (policy) { "AI" -> "ai"; "V" -> "video"; "O" -> "other"; "MATCH" -> "other"; else -> policy }
            assertEquals("policy ${o["input"]}", mapped, trace.policy)
        }
    }
}
