package com.zephyr.app.ui.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LicenseBlocksTest {
    @Test fun splitsAtBlankLines() {
        assertEquals(listOf("a\nb", "c", "d"), licenseBlocks("a\nb\n\n\nc\r\n  \r\nd\n"))
        assertEquals(emptyList<String>(), licenseBlocks("\n\n"))
    }

    /** The bundled files (repo root) keep every non-blank line, in order, after splitting. */
    @Test fun repoLicenseFilesSplitLosslessly() {
        val root = File(System.getProperty("zephyr.fixtures")!!).parentFile.parentFile
        listOf("LICENSE", "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_LICENSES.txt").forEach { name ->
            val text = File(root, name).readText()
            val blocks = licenseBlocks(text)
            assertTrue(name, blocks.isNotEmpty())
            fun lines(s: String) = s.lines().map { it.trimEnd() }.filter { it.isNotBlank() }
            assertEquals(name, lines(text), blocks.flatMap(::lines))
        }
    }

    @Test fun sourceTagFollowsVersion() = assertEquals("mobile-v1.2", sourceTag("1.2"))
}
