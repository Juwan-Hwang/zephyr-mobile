package com.zephyr.app.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

/** docs/geodata.md: bundled snapshot → filesDir/mihomo/ only when absent, via temp name + rename. */
class BundledGeodataTest {
    @get:Rule val tmp = TemporaryFolder()

    private val names = listOf("GeoSite.dat", "geoip.metadb")
    private fun src(name: String): InputStream = ByteArrayInputStream("bundled:$name".toByteArray())
    private fun File.leftovers() = listFiles()!!.filter { it.name.endsWith(BundledGeodata.TMP_SUFFIX) }

    @Test fun absentFilesAreCopied() {
        val home = File(tmp.root, "mihomo") // not created yet: first launch
        val copied = BundledGeodata.installMissing(names, home, open = ::src)
        assertEquals(names, copied)
        names.forEach { assertEquals("bundled:$it", File(home, it).readText()) }
        assertTrue(home.leftovers().isEmpty())
        assertTrue(BundledGeodata.allPresent(names, home))
    }

    @Test fun presentFileIsNeverOverwritten() {
        val home = tmp.newFolder("mihomo")
        File(home, "geoip.metadb").writeText("auto-updated")
        val opened = mutableListOf<String>()
        val copied = BundledGeodata.installMissing(names, home) { opened += it; src(it) }
        assertEquals(listOf("GeoSite.dat"), copied)
        assertEquals(listOf("GeoSite.dat"), opened) // the present file is not even read
        assertEquals("auto-updated", File(home, "geoip.metadb").readText())
        // Second run (every zm_start): nothing to do.
        assertEquals(emptyList<String>(), BundledGeodata.installMissing(names, home, open = ::src))
    }

    @Test fun copyGoesThroughTempNameAndRename() {
        val home = tmp.newFolder("mihomo")
        var seenDuringCopy: List<String> = emptyList()
        BundledGeodata.installMissing(listOf("GeoSite.dat"), home) { name ->
            object : InputStream() {
                val inner = src(name)
                override fun read(): Int = inner.read()
                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    seenDuringCopy = home.list()!!.toList()
                    return inner.read(b, off, len)
                }
            }
        }
        // While bytes were flowing only the temp file existed, never the real name.
        assertTrue(seenDuringCopy.isNotEmpty())
        assertTrue(seenDuringCopy.all { it.startsWith("GeoSite.dat.") && it.endsWith(BundledGeodata.TMP_SUFFIX) })
        assertEquals(listOf("GeoSite.dat"), home.list()!!.toList())
    }

    @Test fun failedCopyLeavesNoPartialFile() {
        val home = tmp.newFolder("mihomo")
        val errors = mutableListOf<String>()
        val copied = BundledGeodata.installMissing(names, home, onError = { n, _ -> errors += n }) { name ->
            if (name == "geoip.metadb") object : InputStream() {
                var n = 0
                override fun read(): Int = if (n++ < 10) 1 else throw IOException("asset truncated")
            } else src(name)
        }
        assertEquals(listOf("GeoSite.dat"), copied)
        assertEquals(listOf("geoip.metadb"), errors)
        assertFalse(File(home, "geoip.metadb").exists())
        assertTrue(home.leftovers().isEmpty())
        assertFalse(BundledGeodata.allPresent(names, home))
    }

    @Test fun staleTempFromCrashIsRemoved() {
        val home = tmp.newFolder("mihomo")
        File(home, "GeoSite.dat.123${BundledGeodata.TMP_SUFFIX}").writeText("half")
        BundledGeodata.installMissing(names, home, open = ::src)
        assertTrue(home.leftovers().isEmpty())
        assertEquals("bundled:GeoSite.dat", File(home, "GeoSite.dat").readText())
    }

    @Test fun nothingBundledMeansNotAllPresent() {
        val home = tmp.newFolder("mihomo")
        assertEquals(emptyList<String>(), BundledGeodata.installMissing(emptyList(), home, open = ::src))
        assertFalse(BundledGeodata.allPresent(emptyList(), home)) // keep the default 15 s download, not "local only"
    }
}
