package com.zephyr.engine.core

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ProfileStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private val yaml = """
        mixed-port: 7890
        proxies:
          - name: "香港 01"
            type: ss
            server: hk.example.com
            port: 443
          - {name: 日本 01, type: vmess, server: jp.example.com, port: 443}
        proxy-groups:
          - name: AI
            type: select
            proxies: [香港 01]
    """.trimIndent()

    private val fakeRuntime = object : ProfileStore.Runtime {
        override fun prepare(yaml: String, secret: String) = "external-controller: 127.0.0.1:9090\nsecret: $secret\n$yaml"
        override fun secret() = "s3cr3t"
    }

    private fun store(fetch: (String) -> ProfileStore.Fetched = { ProfileStore.Fetched(yaml, "upload=100; download=900; total=10000; expire=1800000000", null) }) =
        ProfileStore(tmp.root, fetch, fakeRuntime) { 1_000L }

    @Test fun importUrlWritesProfileActiveAndIndex() {
        val s = store()
        val sub = s.import("https://sub.nebula.cloud/api/v1/client/abc?token=SECRET", true) { all -> all.size * 2L }
        assertEquals("sub-1", sub.id)
        assertEquals("Nebula", sub.name)
        assertEquals(2L, sub.nodeCount)
        assertEquals(1000L, sub.usedBytes); assertEquals(10000L, sub.totalBytes); assertEquals(9000L, sub.remainingBytes)
        assertEquals(1_800_000_000_000L, sub.expiresAt)
        assertFalse("token must never reach the UI", sub.url!!.contains("SECRET"))
        val active = s.activeFile.readText()
        assertTrue(active.startsWith("external-controller: 127.0.0.1:9090\nsecret: s3cr3t"))
        assertEquals("s3cr3t", tmp.root.resolve("profiles/secret").readText())
        // survives restart
        assertEquals(listOf("sub-1"), store().subscriptions.value.map { it.id })
    }

    @Test fun reimportSameUrlUpdatesInPlace() {
        val s = store()
        s.import("https://a.example.com/x", true) { 2 }
        s.import("https://a.example.com/x", true) { 2 }
        assertEquals(1, s.subscriptions.value.size)
    }

    @Test fun rawYamlFromFileAndDelete() {
        val s = store()
        s.import("https://a.example.com/x", true) { 2 }
        val local = s.import(yaml, false) { 4 }
        assertEquals("本地配置", local.name)
        assertEquals(2L, local.nodeCount) // secondary profile counts its own proxies
        assertEquals(2, s.sources().size)
        s.delete("sub-1")
        assertEquals(listOf("sub-2"), s.subscriptions.value.map { it.id })
        assertTrue(s.activeFile.exists())
        s.delete("sub-2")
        assertFalse(s.activeFile.exists())
    }

    @Test fun rejectsNonClashAndBadLinks() {
        val html = store { ProfileStore.Fetched("<html>login</html>", null, null) }
        expect(ErrorCode.SUBSCRIPTION_INVALID) { html.import("https://a.example.com", true) { 0 } }
        expect(ErrorCode.SUBSCRIPTION_INVALID) { store().import("ftp://x", true) { 0 } }
        expect(ErrorCode.SUBSCRIPTION_FETCH_FAILED) { store { error("HTTP 403") }.import("https://a.example.com", true) { 0 } }
        expect(ErrorCode.SUBSCRIPTION_NOT_FOUND) { store().delete("sub-9") }
    }

    @Test fun helpers() {
        assertEquals(2L, ProfileStore.countProxies(yaml))
        assertNull(ProfileStore.parseUserInfo(null).used)
        assertEquals("Nebula Cloud", ProfileStore.dispositionName("attachment; filename*=UTF-8''Nebula%20Cloud.yaml")?.removeSuffix(".yaml"))
        assertEquals("Orbit", ProfileStore.dispositionName("attachment; filename=\"Orbit\""))
    }

    private fun expect(code: ErrorCode, block: () -> Unit) {
        try { block(); fail("expected $code") } catch (e: ZephyrException) { assertEquals(code, e.code) }
    }
}
