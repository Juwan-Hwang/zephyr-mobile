package com.zephyr.engine

import com.zephyr.engine.mock.isUhdName
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** contract/fixtures/uhd-names-v1.json: the Mock's 4K-by-name rule must agree with core case by case (§15.h). */
class UhdNamesFixtureTest {
    @Test fun matchesSharedSamples() {
        val dir = System.getProperty("zephyr.fixtures") ?: "../../../contract/fixtures"
        val cases = Json.parseToJsonElement(File(dir, "uhd-names-v1.json").readText()).jsonObject["cases"]!!.jsonArray
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val o = c.jsonObject
            val name = o["name"]!!.jsonPrimitive.content
            assertEquals(name, o["uhd"]!!.jsonPrimitive.boolean, isUhdName(name))
        }
    }
}
