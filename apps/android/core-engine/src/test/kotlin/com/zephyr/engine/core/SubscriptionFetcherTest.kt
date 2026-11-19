package com.zephyr.engine.core

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrException
import com.zephyr.engine.core.SubscriptionFetcher.Policy
import com.zephyr.engine.core.SubscriptionFetcher.Target
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.net.ServerSocket
import java.util.zip.GZIPOutputStream
import kotlin.concurrent.thread

/** Contract §16.i: request rules, redirect / SSRF decisions, error codes. Local HTTP only, no native library. */
class SubscriptionFetcherTest {
    private fun code(block: () -> Unit): ErrorCode = try { block(); fail("expected an error"); throw AssertionError() } catch (e: ZephyrException) { e.code }

    // ── Pure decisions ──────────────────────────────────────────────────────────────────────────────

    private val kotlinPolicy = Policy(SubscriptionFetcher::kotlinTarget, SubscriptionFetcher::kotlinIsPublic) { error("no dns in this test") }

    @Test fun targetsLikeCore() {
        assertEquals(Target("sub.example.com", 443, true, false), SubscriptionFetcher.kotlinTarget("https://Sub.Example.com/api?token=x"))
        SubscriptionFetcher.kotlinTarget("http://192.168.1.2:8080/s").let { assertEquals(8080, it.port); assertFalse(it.https); assertTrue(it.userEnteredPrivate) }
        assertTrue(SubscriptionFetcher.kotlinTarget("http://nas.local/s").userEnteredPrivate)
        assertTrue(SubscriptionFetcher.kotlinTarget("http://router/s").userEnteredPrivate)
        assertEquals("2001:db8::1", SubscriptionFetcher.kotlinTarget("https://[2001:db8::1]/s").host)
        for (bad in listOf("ftp://a.example/s", "https://", "http://a\texample/s", "zephyr://import?url=x")) {
            assertEquals(bad, ErrorCode.SUBSCRIPTION_INVALID, code { SubscriptionFetcher.kotlinTarget(bad) })
        }
    }

    @Test fun publicAddressesLikeCore() {
        for (ok in listOf("1.1.1.1", "104.16.0.1", "2606:4700::1111", "[2606:4700::1111]")) assertTrue(ok, SubscriptionFetcher.kotlinIsPublic(ok))
        for (bad in listOf("10.0.0.1", "127.0.0.1", "169.254.169.254", "172.16.0.1", "192.168.1.1", "100.64.0.1", "198.18.0.5", "0.0.0.0",
            "::1", "fe80::1", "fd00::1", "::ffff:192.168.1.1", "224.0.0.1", "example.com", "")) {
            assertFalse(bad, SubscriptionFetcher.kotlinIsPublic(bad))
        }
    }

    @Test fun redirectRules() {
        val pub = SubscriptionFetcher.kotlinTarget("https://a.example/s")
        val (next, t) = SubscriptionFetcher.redirect(kotlinPolicy, pub, "https://a.example/s", pub, "/v2?x=1", 0)
        assertEquals("https://a.example/v2?x=1", next); assertEquals("a.example", t.host)
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.redirect(kotlinPolicy, pub, "https://a.example/s", pub, "http://a.example/s", 0) })
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.redirect(kotlinPolicy, pub, "https://a.example/s", pub, "https://b.example/s", 5) })
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.redirect(kotlinPolicy, pub, "https://a.example/s", pub, null, 0) })
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.redirect(kotlinPolicy, pub, "https://a.example/s", pub, "ftp://a.example/", 0) })
        // a user-typed private host may only redirect to itself
        val nas = SubscriptionFetcher.kotlinTarget("http://nas.local/s")
        SubscriptionFetcher.redirect(kotlinPolicy, nas, "http://nas.local/s", nas, "http://nas.local/t", 0)
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.redirect(kotlinPolicy, nas, "http://nas.local/s", nas, "http://evil.example/t", 0) })
    }

    @Test fun ssrfGate() {
        val t = Target("sub.example", 443, true, false)
        val resolvesTo = { ips: List<String> -> Policy({ t }, SubscriptionFetcher::kotlinIsPublic) { ips } }
        assertEquals(listOf("1.1.1.1"), SubscriptionFetcher.addresses(resolvesTo(listOf("1.1.1.1")), t, viaProxy = false))
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.addresses(resolvesTo(listOf("1.1.1.1", "10.0.0.1")), t, false) })
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.addresses(resolvesTo(listOf("::ffff:127.0.0.1")), t, true) })
        val noDns = Policy({ t }, SubscriptionFetcher::kotlinIsPublic) { throw java.net.UnknownHostException(it) }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.addresses(noDns, t, viaProxy = false) })
        assertEquals(emptyList<String>(), SubscriptionFetcher.addresses(noDns, t, viaProxy = true)) // mihomo resolves remotely
        val lan = Target("192.168.1.2", 80, false, true)
        assertEquals(listOf("192.168.1.2"), SubscriptionFetcher.addresses(Policy({ lan }, { false }) { listOf("192.168.1.2") }, lan, false))
    }

    @Test fun bodyAndNames() {
        assertEquals("a: 1", SubscriptionFetcher.utf8(byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "a: 1".toByteArray()))
        assertEquals(ErrorCode.SUBSCRIPTION_INVALID, code { SubscriptionFetcher.utf8(byteArrayOf(0xC3.toByte(), 0x28)) })
        assertEquals("Nebula Cloud", SubscriptionFetcher.nameFrom("attachment; filename*=UTF-8''Nebula%20Cloud.yaml"))
        assertEquals("orbit", SubscriptionFetcher.nameFrom("attachment; filename=\"orbit.yml\""))
        assertEquals(64, SubscriptionFetcher.nameFrom("attachment; filename=\"${"a".repeat(100)}.yaml\"")!!.toByteArray().size)
        assertTrue(SubscriptionFetcher.nameFrom("attachment; filename*=UTF-8''${"%E5%AE%B6".repeat(30)}.yaml")!!.toByteArray().size <= 64)
        assertNull(SubscriptionFetcher.nameFrom(null))
        assertEquals(
            "Zephyr/1.2.0 (Android 15) clash.meta mihomo/v1.19.0",
            SubscriptionFetcher.userAgent("1.2.0", "15", "v1.19.0"),
        )
    }

    // ── Over the wire (127.0.0.1) ───────────────────────────────────────────────────────────────────

    private val servers = mutableListOf<ServerSocket>()
    @After fun close() { servers.forEach { runCatching { it.close() } } }

    /** Serves each connection with [handle] (request head → raw response bytes). */
    private fun server(handle: (String) -> ByteArray): Int {
        val ss = ServerSocket(0, 50, java.net.InetAddress.getLoopbackAddress()).also { servers += it }
        thread(isDaemon = true) {
            while (!ss.isClosed) {
                val s = runCatching { ss.accept() }.getOrNull() ?: break
                thread(isDaemon = true) {
                    s.use {
                        val head = StringBuilder()
                        val inp = it.getInputStream()
                        while (!head.endsWith("\r\n\r\n")) { val b = inp.read(); if (b < 0) break; head.append(b.toChar()) }
                        it.getOutputStream().write(handle(head.toString())); it.getOutputStream().flush()
                    }
                }
            }
        }
        return ss.localPort
    }

    private fun resp(status: String, headers: List<String> = emptyList(), body: ByteArray = ByteArray(0), chunked: Boolean = false): ByteArray {
        val out = ByteArrayOutputStream()
        out.write("HTTP/1.1 $status\r\n".toByteArray())
        headers.forEach { out.write("$it\r\n".toByteArray()) }
        if (chunked) {
            out.write("Transfer-Encoding: chunked\r\n\r\n".toByteArray())
            body.toList().chunked(7).forEach { c -> out.write("${Integer.toHexString(c.size)}\r\n".toByteArray()); out.write(c.toByteArray()); out.write("\r\n".toByteArray()) }
            out.write("0\r\n\r\n".toByteArray())
        } else {
            out.write("Content-Length: ${body.size}\r\n\r\n".toByteArray()); out.write(body)
        }
        return out.toByteArray()
    }

    private fun gzip(s: String): ByteArray = ByteArrayOutputStream().also { b -> GZIPOutputStream(b).use { it.write(s.toByteArray()) } }.toByteArray()

    /** The twin with real (literal-only here) address lookup. */
    private val wirePolicy = Policy(SubscriptionFetcher::kotlinTarget, SubscriptionFetcher::kotlinIsPublic)

    private fun opts(policy: Policy = wirePolicy, route: SubscriptionFetcher.Route? = null, online: Boolean = true) =
        SubscriptionFetcher.Options(policy, "Zephyr/test (Android 15) clash.meta mihomo/v1", route, online)

    @Test fun fetchesGzipChunkedWithHeaders() {
        var seen = ""
        val port = server { head ->
            seen = head
            resp("200 OK", listOf("Content-Encoding: gzip", "Subscription-Userinfo: upload=1; download=2; total=3", "Content-Disposition: attachment; filename=\"orbit.yaml\""), gzip("proxies: []"), chunked = true)
        }
        val got = SubscriptionFetcher.fetch("http://127.0.0.1:$port/sub?t=1", opts())
        assertEquals("proxies: []", got.body)
        assertEquals("upload=1; download=2; total=3", got.userInfo)
        assertEquals("orbit", got.fileName)
        assertTrue(seen.startsWith("GET /sub?t=1 HTTP/1.1\r\n"))
        assertTrue(seen.contains("User-Agent: Zephyr/test (Android 15) clash.meta mihomo/v1\r\n"))
        assertTrue(seen.contains("Accept: */*\r\n"))
        assertTrue(seen.contains("Accept-Encoding: gzip\r\n"))
        assertFalse(seen.contains("Cookie", ignoreCase = true))
    }

    @Test fun followsRedirectsToTheSameHostAndStopsAtFive() {
        val port = server { head ->
            val n = Regex("GET /r(\\d+)").find(head)?.groupValues?.get(1)?.toInt()
            if (n != null && n < 3) resp("302 Found", listOf("Location: /r${n + 1}")) else resp("200 OK", body = "ok".toByteArray())
        }
        assertEquals("ok", SubscriptionFetcher.fetch("http://127.0.0.1:$port/r0", opts()).body)
        val loop = server { resp("301 Moved", listOf("Location: /again")) }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.fetch("http://127.0.0.1:$loop/x", opts()) })
        // A user-typed private host never redirects somewhere else.
        val away = server { resp("302 Found", listOf("Location: http://localhost:1/x")) }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.fetch("http://127.0.0.1:$away/x", opts()) })
    }

    @Test fun errorCodes() {
        val notFound = server { resp("404 Not Found", body = "nope".toByteArray()) }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.fetch("http://127.0.0.1:$notFound/x", opts()) })
        val latin = server { resp("200 OK", body = byteArrayOf(0xE9.toByte(), 0x20, 0x41)) }
        assertEquals(ErrorCode.SUBSCRIPTION_INVALID, code { SubscriptionFetcher.fetch("http://127.0.0.1:$latin/x", opts()) })
        assertEquals(ErrorCode.NETWORK_UNAVAILABLE, code { SubscriptionFetcher.fetch("http://127.0.0.1:1/x", opts(online = false)) })
        assertEquals(ErrorCode.SUBSCRIPTION_INVALID, code { SubscriptionFetcher.fetch("ftp://127.0.0.1/x", opts()) })
        val closed = ServerSocket(0).let { val p = it.localPort; it.close(); p }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.fetch("http://127.0.0.1:$closed/x", opts()) })
    }

    @Test fun publicHostMustResolvePublic() {
        val port = server { resp("200 OK", body = "ok".toByteArray()) }
        val t = Target("sub.test", port, false, false)
        val ok = Policy({ t }, { true }) { listOf("127.0.0.1") }
        assertEquals("ok", SubscriptionFetcher.fetch("http://sub.test:$port/x", opts(ok)).body)
        val ssrf = Policy({ t }, SubscriptionFetcher::kotlinIsPublic) { listOf("127.0.0.1") }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.fetch("http://sub.test:$port/x", opts(ssrf)) })
    }

    @Test fun throughTheLoopbackProxyWithCredentials() {
        var seen = ""
        val proxy = server { head -> seen = head; resp("200 OK", body = "via proxy".toByteArray()) }
        val t = Target("blocked.example", 80, false, false)
        val p = Policy({ t }, { true }) { throw java.net.UnknownHostException(it) } // blocked locally, mihomo resolves
        val got = SubscriptionFetcher.fetch("http://blocked.example/sub", opts(p, SubscriptionFetcher.Route(proxy, "zephyr:secret")))
        assertEquals("via proxy", got.body)
        assertTrue(seen.startsWith("GET http://blocked.example/sub HTTP/1.1\r\n"))
        assertTrue(seen.contains("Proxy-Authorization: Basic " + java.util.Base64.getEncoder().encodeToString("zephyr:secret".toByteArray())))
    }

    @Test fun downloadKeepsOldFileOnFailure() {
        val dir = kotlin.io.path.createTempDirectory("geo").toFile()
        val dest = java.io.File(dir, "geosite.dat").apply { writeText("old") }
        val big = server { resp("200 OK", body = ByteArray(2048)) }
        assertEquals(ErrorCode.SUBSCRIPTION_FETCH_FAILED, code { SubscriptionFetcher.download("http://127.0.0.1:$big/g", dest, opts(), maxBytes = 1024) })
        assertEquals("old", dest.readText())
        assertFalse(java.io.File(dir, "geosite.dat.part").exists())
        val small = server { resp("200 OK", body = "new".toByteArray()) }
        SubscriptionFetcher.download("http://127.0.0.1:$small/g", dest, opts())
        assertEquals("new", dest.readText())
        dir.deleteRecursively()
    }
}
