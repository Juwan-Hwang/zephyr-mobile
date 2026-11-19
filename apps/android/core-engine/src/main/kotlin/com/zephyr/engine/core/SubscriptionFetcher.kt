package com.zephyr.engine.core

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrException
import java.io.ByteArrayOutputStream
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.Base64
import java.util.zip.GZIPInputStream
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Platform half of subscription import (contract §16.i, E35): HTTP only. Parsing, validation, storage, userinfo,
 * redaction and the node rebuild live in core-mobile, shared with iOS. Used for import, manual and automatic updates,
 * and rule-set / GEO downloads (their URLs come from subscriptions and go through the same SSRF checks).
 *
 * - before any request: `fetchTarget(url)` (invalid → `subscription_invalid`, nothing is sent);
 * - `GET`, no cookies / cache / credentials, UA `Zephyr/<app> (Android <os>) clash.meta mihomo/<core>`, `Accept` any,
 *   `Accept-Encoding: gzip` (decompressed here; the 32 MB cap counts decompressed bytes);
 * - 15 s to connect, 30 s for the whole request including redirects and the body;
 * - at most 5 redirects, followed by hand, each one validated again; https → http is refused;
 * - only 2xx; body must be UTF‑8 (BOM allowed) else `subscription_invalid`;
 * - SSRF: unless the user typed a private host (`userEnteredPrivate`), every DNS answer must pass
 *   `isPublicFetchAddress`, and the connection goes to the address that was checked (no second lookup);
 *   a user-typed private host may only redirect to itself;
 * - while the tunnel runs, requests go through mihomo's loopback mixed port with its credential (the app itself is
 *   excluded from the VPN), so a blocked subscription host updates once connected — same as iOS;
 * - the system HTTP proxy is never read.
 * Errors: offline → `network_unavailable`; DNS, timeout, TLS, non-2xx, too large, redirects, SSRF → `subscription_fetch_failed`.
 */
object SubscriptionFetcher {
    const val MAX_BYTES = 32 * 1024 * 1024
    const val MAX_GEO_BYTES = 64L * 1024 * 1024
    const val CONNECT_TIMEOUT_MS = 15_000
    const val TOTAL_TIMEOUT_MS = 30_000L
    const val MAX_REDIRECTS = 5
    const val NAME_MAX_BYTES = 64

    data class Fetched(val body: String, val userInfo: String?, val fileName: String?)

    /** Result of `fetchTarget` (core) — kept as a plain class so the decisions are testable without JNA. */
    data class Target(val host: String, val port: Int, val https: Boolean, val userEnteredPrivate: Boolean)

    /**
     * The core's two judgements plus DNS. [target] throws `subscription_invalid` for a bad URL. [resolve] returns the
     * addresses as literals, or throws [java.net.UnknownHostException].
     */
    class Policy(
        val target: (String) -> Target,
        val isPublic: (String) -> Boolean,
        val resolve: (String) -> List<String> = { h -> InetAddress.getAllByName(h).map { it.hostAddress ?: "" } },
    )

    /** mihomo's loopback mixed port while the tunnel runs; [auth] = "user:password" or null. */
    data class Route(val proxyPort: Int, val auth: String?)

    class Options(
        val policy: Policy,
        val userAgent: String,
        val route: Route? = null,
        val online: Boolean = true,
        val totalTimeoutMs: Long = TOTAL_TIMEOUT_MS,
        val connectTimeoutMs: Int = CONNECT_TIMEOUT_MS,
        val clock: () -> Long = System::currentTimeMillis,
    )

    fun userAgent(appVersion: String, osVersion: String?, mihomoVersion: String?): String =
        "Zephyr/$appVersion (Android ${osVersion ?: "unknown"}) clash.meta mihomo/${mihomoVersion?.takeIf { it.isNotBlank() } ?: "unknown"}"

    // ── Pure decisions (unit-tested) ──────────────────────────────────────────────────────────────────

    fun failed(why: String) = ZephyrException(ErrorCode.SUBSCRIPTION_FETCH_FAILED, why)
    fun invalid(why: String) = ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, why)

    /**
     * Where a redirect may go (§16.i ② / ③): resolved against [from], at most [MAX_REDIRECTS] hops, never https → http,
     * a valid target, and — when the user typed a private host — the same host only. Returns the next URL and target.
     */
    fun redirect(policy: Policy, first: Target, fromUrl: String, from: Target, location: String?, hops: Int): Pair<String, Target> {
        if (hops >= MAX_REDIRECTS) throw failed("too many redirects")
        if (location.isNullOrBlank()) throw failed("redirect without Location")
        val next = runCatching { URI(fromUrl).resolve(location.trim()).toString() }.getOrElse { throw failed("bad redirect") }
        val t = try { policy.target(next) } catch (e: ZephyrException) { throw failed("redirect target invalid") }
        if (from.https && !t.https) throw failed("https → http redirect refused")
        if (first.userEnteredPrivate && t.host != first.host) throw failed("private host may only redirect to itself")
        return next to t
    }

    /**
     * SSRF gate (§16.i ③): the addresses to connect to. A user-typed private host is not checked. Otherwise every
     * answer must be public. Through the tunnel's proxy a failed local lookup is allowed (mihomo resolves remotely; a
     * blocked domain may not resolve locally), but an answer that is private still refuses.
     */
    fun addresses(policy: Policy, t: Target, viaProxy: Boolean): List<String> {
        if (t.userEnteredPrivate) return if (viaProxy) emptyList() else resolveOrFail(policy, t.host)
        val list = try { policy.resolve(t.host) } catch (e: IOException) {
            if (viaProxy) return emptyList() else throw failed("dns: ${e.message}")
        }
        if (list.isEmpty()) { if (viaProxy) return emptyList() else throw failed("dns: no address") }
        if (!list.all(policy.isPublic)) throw failed("ssrf: ${t.host} resolves to a non-public address")
        return list
    }

    private fun resolveOrFail(policy: Policy, host: String): List<String> =
        try { policy.resolve(host).ifEmpty { throw failed("dns: no address") } } catch (e: IOException) { throw failed("dns: ${e.message}") }

    /** UTF‑8 only (a BOM is dropped); anything else is not a subscription. */
    fun utf8(bytes: ByteArray): String {
        val start = if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()) 3 else 0
        val dec = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        return try { dec.decode(ByteBuffer.wrap(bytes, start, bytes.size - start)).toString() } catch (_: CharacterCodingException) { throw invalid("body is not UTF-8") }
    }

    /** Content-Disposition: attachment; filename*=UTF-8''Nebula%20Cloud.yaml */
    fun dispositionName(h: String?): String? {
        if (h == null) return null
        Regex("filename\\*=(?:UTF-8'')?([^;]+)", RegexOption.IGNORE_CASE).find(h)?.let { return java.net.URLDecoder.decode(it.groupValues[1].trim('"'), "UTF-8") }
        return Regex("filename=\"?([^\";]+)", RegexOption.IGNORE_CASE).find(h)?.groupValues?.get(1)
    }

    /** §16.i ②: the name an import takes from the response — file name without extension, at most 64 bytes. */
    fun nameFrom(disposition: String?): String? {
        val raw = dispositionName(disposition)?.substringAfterLast('/')?.trim() ?: return null
        val stem = (if (raw.contains('.')) raw.substringBeforeLast('.') else raw).trim()
        if (stem.isEmpty()) return null
        val out = StringBuilder()
        var bytes = 0
        var i = 0
        while (i < stem.length) {
            val cp = stem.codePointAt(i)
            val n = String(Character.toChars(cp)).toByteArray(Charsets.UTF_8).size
            if (bytes + n > NAME_MAX_BYTES) break
            out.appendCodePoint(cp); bytes += n; i += Character.charCount(cp)
        }
        return out.toString().trim().ifEmpty { null }
    }

    // ── Network ───────────────────────────────────────────────────────────────────────────────────────

    /** Subscription / rule-set text. */
    fun fetch(url: String, o: Options): Fetched {
        val r = request(url, o)
        r.use { resp ->
            val bytes = readCapped(resp.body, MAX_BYTES.toLong(), resp.deadline, o.clock)
            return Fetched(utf8(bytes), resp.header("subscription-userinfo"), nameFrom(resp.header("content-disposition")))
        }
    }

    /**
     * Streams a binary file (geosite / geoip .dat) to [dest] through a temp file; on any failure the old file stays
     * (contract §14.v). Same rules as [fetch] (§16.i: GEO URLs come from subscriptions).
     */
    fun download(url: String, dest: java.io.File, o: Options, maxBytes: Long = MAX_GEO_BYTES) {
        request(url, o).use { resp ->
            dest.parentFile?.mkdirs()
            // Unique temp per call: overlapping GEO refreshes must not truncate or rename each other's data.
            val tmp = java.io.File.createTempFile(dest.name + ".", ".part", dest.absoluteFile.parentFile)
            try {
                tmp.outputStream().use { out -> copyCapped(resp.body, out, maxBytes, resp.deadline, o.clock) }
                if (!tmp.renameTo(dest)) throw failed("rename failed")
            } finally { tmp.delete() }
        }
    }

    class Response(val status: Int, private val headers: Map<String, String>, val body: InputStream, val deadline: Long, private val socket: Socket) : AutoCloseable {
        fun header(name: String): String? = headers[name.lowercase()]
        override fun close() { runCatching { socket.close() } }
    }

    /** Validates, follows redirects by hand, and returns the 2xx response with its body stream (caller closes). */
    fun request(url: String, o: Options): Response {
        if (!o.online) throw ZephyrException(ErrorCode.NETWORK_UNAVAILABLE, "offline")
        val first = o.policy.target(url)
        val deadline = o.clock() + o.totalTimeoutMs
        var current = url
        var t = first
        var hops = 0
        while (true) {
            val resp = try { once(current, t, o, deadline) } catch (e: ZephyrException) { throw e } catch (e: IOException) {
                throw failed("${e.javaClass.simpleName}: ${e.message}")
            }
            when (resp.status) {
                in 200..299 -> return resp
                301, 302, 303, 307, 308 -> {
                    val loc = resp.header("location")
                    resp.close()
                    val (n, nt) = redirect(o.policy, first, current, t, loc, hops)
                    current = n; t = nt; hops++
                }
                else -> { resp.close(); throw failed("HTTP ${resp.status}") }
            }
        }
    }

    private fun once(url: String, t: Target, o: Options, deadline: Long): Response {
        val u = URI(url)
        val path = (u.rawPath?.ifEmpty { "/" } ?: "/") + (u.rawQuery?.let { "?$it" } ?: "")
        // A user-typed LAN host is fetched directly: the loopback proxy would only send it back to the LAN.
        val route = o.route?.takeIf { !t.userEnteredPrivate }
        val addrs = addresses(o.policy, t, viaProxy = route != null)
        val hostHeader = (if (t.host.contains(':')) "[${t.host}]" else t.host) + if ((t.https && t.port == 443) || (!t.https && t.port == 80)) "" else ":${t.port}"
        var sock = Socket()
        try {
            if (route != null) {
                sock.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), route.proxyPort), o.connectTimeoutMs)
            } else {
                connectAny(sock, addrs, t.port, o.connectTimeoutMs).also { sock = it }
            }
            fun remaining(): Int = (deadline - o.clock()).coerceAtLeast(1).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            sock.soTimeout = remaining()
            val proxyAuth = route?.auth?.let { "Proxy-Authorization: Basic " + Base64.getEncoder().encodeToString(it.toByteArray()) + "\r\n" } ?: ""
            var stream: Socket = sock
            var requestTarget = path
            if (route != null && t.https) {
                val authority = (if (t.host.contains(':')) "[${t.host}]" else t.host) + ":${t.port}"
                sock.getOutputStream().write("CONNECT $authority HTTP/1.1\r\nHost: $authority\r\n$proxyAuth\r\n".toByteArray())
                val head = readHead(sock.getInputStream(), deadline, o.clock)
                if (statusOf(head) != 200) throw failed("proxy CONNECT ${statusOf(head)}")
            } else if (route != null) {
                requestTarget = "http://$hostHeader$path"
            }
            if (t.https) {
                val tls = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(sock, t.host, t.port, true) as SSLSocket
                tls.sslParameters = tls.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
                tls.soTimeout = remaining()
                tls.startHandshake()
                stream = tls
            }
            val req = buildString {
                append("GET ").append(requestTarget).append(" HTTP/1.1\r\n")
                append("Host: ").append(hostHeader).append("\r\n")
                append("User-Agent: ").append(o.userAgent).append("\r\n")
                append("Accept: */*\r\nAccept-Encoding: gzip\r\nConnection: close\r\n")
                if (route != null && !t.https) append(proxyAuth)
                append("\r\n")
            }
            stream.getOutputStream().write(req.toByteArray())
            stream.getOutputStream().flush()
            val input = java.io.BufferedInputStream(stream.getInputStream())
            val head = readHead(input, deadline, o.clock)
            val status = statusOf(head) ?: throw failed("bad response")
            val headers = parseHeaders(head)
            var body: InputStream = when {
                headers["transfer-encoding"]?.contains("chunked", ignoreCase = true) == true -> ChunkedInputStream(input)
                headers["content-length"]?.trim()?.toLongOrNull() != null -> BoundedInputStream(input, headers["content-length"]!!.trim().toLong())
                else -> input
            }
            if (headers["content-encoding"]?.contains("gzip", ignoreCase = true) == true && status in 200..299) body = GZIPInputStream(body)
            return Response(status, headers, body, deadline, stream)
        } catch (t: Throwable) {
            runCatching { sock.close() }
            throw t
        }
    }

    private fun connectAny(sock: Socket, addrs: List<String>, port: Int, timeout: Int): Socket {
        var last: IOException? = null
        var s = sock
        for (a in addrs) {
            try {
                s.connect(InetSocketAddress(InetAddress.getByName(a), port), timeout) // literal: no DNS
                return s
            } catch (e: IOException) { last = e; runCatching { s.close() }; s = Socket() }
        }
        throw last ?: IOException("no address")
    }

    /** soTimeout is per read, so a server trickling bytes is cut off by the total deadline here (§16.i 30 s). */
    private fun readHead(input: InputStream, deadline: Long, clock: () -> Long): String {
        val sb = StringBuilder()
        while (sb.length < 65_536) {
            if (clock() > deadline) throw failed("timeout")
            val b = input.read()
            if (b < 0) break
            sb.append(b.toChar())
            if (sb.endsWith("\r\n\r\n")) break
        }
        return sb.toString()
    }

    private fun statusOf(head: String): Int? = head.lineSequence().firstOrNull()?.split(' ')?.getOrNull(1)?.toIntOrNull()

    /** Header names lower-cased; repeated headers keep the first value. Values are ISO‑8859‑1 bytes → UTF‑8 text. */
    private fun parseHeaders(head: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        head.split("\r\n").drop(1).forEach { line ->
            val i = line.indexOf(':')
            if (i > 0) {
                val k = line.substring(0, i).trim().lowercase()
                val v = String(line.substring(i + 1).trim().toByteArray(Charsets.ISO_8859_1), Charsets.UTF_8)
                out.putIfAbsent(k, v)
            }
        }
        return out
    }

    private fun readCapped(input: InputStream, max: Long, deadline: Long, clock: () -> Long): ByteArray {
        val buf = ByteArrayOutputStream()
        copyCapped(input, buf, max, deadline, clock)
        return buf.toByteArray()
    }

    private fun copyCapped(input: InputStream, out: java.io.OutputStream, max: Long, deadline: Long, clock: () -> Long) {
        val b = ByteArray(64 * 1024)
        var total = 0L
        try {
            while (true) {
                if (clock() > deadline) throw failed("timeout")
                val r = input.read(b)
                if (r < 0) break
                total += r
                if (total > max) throw failed("too large")
                out.write(b, 0, r)
            }
        } catch (e: IOException) { throw failed("${e.javaClass.simpleName}: ${e.message}") }
    }

    private class BoundedInputStream(input: InputStream, private var left: Long) : FilterInputStream(input) {
        override fun read(): Int = if (left <= 0) -1 else super.read().also { if (it >= 0) left-- }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (left <= 0) return -1
            val n = super.read(b, off, minOf(len.toLong(), left).toInt())
            if (n > 0) left -= n
            return n
        }
    }

    private class ChunkedInputStream(private val input: InputStream) : InputStream() {
        private var left = 0L
        private var done = false
        private fun line(): String {
            val sb = StringBuilder()
            while (true) {
                val c = input.read()
                if (c < 0) throw IOException("truncated chunk")
                if (c == '\n'.code) break
                if (c != '\r'.code) sb.append(c.toChar())
                if (sb.length > 1024) throw IOException("bad chunk")
            }
            return sb.toString()
        }
        private fun next(): Boolean {
            if (done) return false
            if (left == 0L) {
                val size = line().substringBefore(';').trim().toLongOrNull(16) ?: throw IOException("bad chunk size")
                if (size == 0L) { done = true; while (line().isNotEmpty()) Unit; return false }
                left = size
            }
            return true
        }
        override fun read(): Int {
            val one = ByteArray(1)
            return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 0xFF
        }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (!next()) return -1
            val n = input.read(b, off, minOf(len.toLong(), left).toInt())
            if (n < 0) throw IOException("truncated chunk")
            left -= n
            if (left == 0L) line() // CRLF after the chunk
            return n
        }
    }

    // ── Kotlin twin of the core's policy, only for builds without the native library (JVM tests, previews) ──

    private val INTERNAL_SUFFIXES = listOf(".local", ".lan", ".home", ".internal", ".intranet", ".localdomain", ".home.arpa", ".corp")
    private val IPV4 = Regex("^\\d{1,3}(\\.\\d{1,3}){3}$")

    fun kotlinTarget(url: String): Target {
        val s = url.trim()
        if (s.any { it.isISOControl() || it == ' ' }) throw invalid("control characters")
        val u = runCatching { URI(s) }.getOrElse { throw invalid("bad url") }
        val scheme = u.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") throw invalid("scheme")
        val host = u.host?.trim('[', ']')?.lowercase()?.takeIf { it.isNotEmpty() } ?: throw invalid("no host")
        val https = scheme == "https"
        val port = if (u.port > 0) u.port else if (https) 443 else 80
        val literal = IPV4.matches(host) || host.contains(':')
        val private = if (literal) !kotlinIsPublic(host) else !host.contains('.') || INTERNAL_SUFFIXES.any { host.endsWith(it) }
        return Target(host, port, https, private)
    }

    fun kotlinIsPublic(ip: String): Boolean {
        val s = ip.trim().trim('[', ']')
        if (!(IPV4.matches(s) || s.contains(':'))) return false
        val a = runCatching { InetAddress.getByName(s) }.getOrNull() ?: return false // literal: no DNS
        val b = a.address
        fun v4(x: ByteArray): Boolean {
            val o0 = x[0].toInt() and 0xFF; val o1 = x[1].toInt() and 0xFF; val o2 = x[2].toInt() and 0xFF
            return !(o0 == 0 || o0 == 10 || o0 == 127 || o0 >= 224 || (o0 == 169 && o1 == 254) || (o0 == 172 && o1 in 16..31) ||
                (o0 == 192 && o1 == 168) || (o0 == 100 && o1 in 64..127) || (o0 == 198 && o1 in 18..19) ||
                (o0 == 192 && o1 == 0 && (o2 == 0 || o2 == 2)) || (o0 == 198 && o1 == 51 && o2 == 100) || (o0 == 203 && o1 == 0 && o2 == 113))
        }
        if (b.size == 4) return v4(b)
        // IPv6: mapped / compatible / NAT64-embedded IPv4 are judged as that IPv4.
        val mapped = (0 until 10).all { b[it] == 0.toByte() } && b[10] == 0xFF.toByte() && b[11] == 0xFF.toByte()
        if (mapped) return v4(b.copyOfRange(12, 16))
        if ((0 until 12).all { b[it] == 0.toByte() }) return false // ::, ::1, IPv4-compatible
        val nat64 = b[0] == 0.toByte() && b[1] == 0x64.toByte() && b[2] == 0xFF.toByte() && b[3] == 0x9B.toByte()
        if (nat64) return v4(b.copyOfRange(12, 16))
        val first = b[0].toInt() and 0xFF
        if (first == 0xFF || (first and 0xFE) == 0xFC) return false // multicast, ULA
        if (first == 0xFE && (b[1].toInt() and 0xC0) == 0x80) return false // link-local
        if (first == 0xFE && (b[1].toInt() and 0xC0) == 0xC0) return false // site-local (deprecated)
        if (first == 0x20 && b[1] == 0x01.toByte() && b[2] == 0x0D.toByte() && b[3] == 0xB8.toByte()) return false // documentation
        return true
    }

    /** Core policy when the native library is loaded, otherwise the Kotlin twin. */
    fun corePolicy(native: Boolean): Policy = if (native) Policy(
        target = { url ->
            try {
                com.zephyr.core.mobile.fetchTarget(url).let { Target(it.host, it.port.toInt(), it.https, it.userEnteredPrivate) }
            } catch (e: com.zephyr.core.mobile.MobileException) { throw invalid(e.message ?: "invalid url") }
        },
        isPublic = { ip -> com.zephyr.core.mobile.isPublicFetchAddress(ip) },
    ) else Policy(::kotlinTarget, ::kotlinIsPublic)
}
