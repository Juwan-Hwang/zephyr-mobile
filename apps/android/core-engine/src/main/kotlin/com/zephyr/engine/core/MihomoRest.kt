package com.zephyr.engine.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.URLEncoder

/**
 * Client for mihomo's own REST controller, reached over the unix socket `zm_start` opens
 * (`external-controller-unix`, inside the app's private files dir: no TCP port, no secret on the wire).
 *
 * Tiny HTTP/1.1 (one request per connection, `Connection: close`, Content-Length or chunked) so the
 * engine needs no HTTP stack and the same code runs over Android's LocalSocket and a JVM test socket.
 */
class MihomoRest(private val dial: Dialer) {

    fun interface Dialer { fun dial(): Conn }
    interface Conn : Closeable { val input: InputStream; val output: OutputStream }

    class HttpException(val status: Int, body: String) : IOException("HTTP $status: ${body.take(200)}")

    // ── Model (only what Zephyr maps) ─────────────────────────────────────────────────────────────
    data class Proxy(val name: String, val type: String, val now: String?, val all: List<String>, val lastDelay: Int?, val lastTestAt: Long?)
    data class Conn0(
        val id: String, val host: String, val process: String?, val chains: List<String>, val rule: String, val rulePayload: String,
        val up: Long, val down: Long, val startMillis: Long,
    )

    // ── Endpoints ─────────────────────────────────────────────────────────────────────────────────
    fun version(): String? = obj("GET", "/version")["version"]?.jsonPrimitive?.contentOrNull

    fun proxies(): Map<String, Proxy> = obj("GET", "/proxies")["proxies"]?.jsonObject.orEmpty().mapValues { (name, v) -> proxy(name, v.jsonObject) }

    fun select(group: String, member: String) { call("PUT", "/proxies/${seg(group)}", """{"name":${JsonPrimitive(member)}}""") }

    /** Tests every member of [group]; returns name → delay ms (absent = timeout). Updates mihomo's history too. */
    fun groupDelay(group: String, url: String = TEST_URL, timeoutMs: Int = 5_000): Map<String, Int> =
        obj("GET", "/group/${seg(group)}/delay?url=${URLEncoder.encode(url, "UTF-8")}&timeout=$timeoutMs")
            .mapNotNull { (k, v) -> (v as? JsonPrimitive)?.intOrNull?.takeIf { it > 0 }?.let { k to it } }.toMap()

    fun connections(): List<Conn0> = obj("GET", "/connections")["connections"].let { it as? JsonArray }.orEmpty().map { conn(it.jsonObject) }

    fun closeConnection(id: String) { call("DELETE", "/connections/${seg(id)}") }
    fun closeAll() { call("DELETE", "/connections") }
    fun setMode(mode: String) { call("PATCH", "/configs", """{"mode":"$mode"}""") }

    // ── Wire ──────────────────────────────────────────────────────────────────────────────────────
    private fun obj(method: String, path: String, body: String? = null): JsonObject =
        call(method, path, body).takeIf { it.isNotBlank() }?.let { JSON.parseToJsonElement(it).jsonObject } ?: JsonObject(emptyMap())

    internal fun call(method: String, path: String, body: String? = null): String = dial.dial().use { c ->
        val bytes = body?.toByteArray(Charsets.UTF_8)
        val head = buildString {
            append("$method $path HTTP/1.1\r\nHost: mihomo\r\nConnection: close\r\nAccept: application/json\r\n")
            if (bytes != null) append("Content-Type: application/json\r\nContent-Length: ${bytes.size}\r\n")
            append("\r\n")
        }
        c.output.write(head.toByteArray(Charsets.US_ASCII)); bytes?.let(c.output::write); c.output.flush()
        val (status, text) = readResponse(c.input)
        if (status !in 200..299) throw HttpException(status, text)
        text
    }

    companion object {
        const val TEST_URL = "https://www.gstatic.com/generate_204"
        private val JSON = Json { ignoreUnknownKeys = true; isLenient = true }
        private const val MAX_BODY = 16 * 1024 * 1024

        private fun seg(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

        internal fun readResponse(input: InputStream): Pair<Int, String> {
            val status = readLine(input)?.split(' ')?.getOrNull(1)?.toIntOrNull() ?: throw IOException("bad status line")
            var length = -1; var chunked = false
            while (true) {
                val l = readLine(input) ?: break
                if (l.isEmpty()) break
                val i = l.indexOf(':'); if (i < 0) continue
                when (l.substring(0, i).trim().lowercase()) {
                    "content-length" -> length = l.substring(i + 1).trim().toInt()
                    "transfer-encoding" -> chunked = l.substring(i + 1).contains("chunked", ignoreCase = true)
                }
            }
            val out = ByteArrayOutputStream()
            when {
                chunked -> while (true) {
                    val size = (readLine(input) ?: break).substringBefore(';').trim().toInt(16)
                    if (size == 0) break
                    copy(input, out, size); readLine(input)
                }
                length >= 0 -> copy(input, out, length)
                else -> { val b = ByteArray(8192); while (true) { val r = input.read(b); if (r < 0) break; out.write(b, 0, r); check(out.size() <= MAX_BODY) } }
            }
            return status to out.toString(Charsets.UTF_8.name())
        }

        private fun copy(input: InputStream, out: ByteArrayOutputStream, n: Int) {
            require(n <= MAX_BODY) { "body too large" }
            val b = ByteArray(minOf(n, 8192).coerceAtLeast(1)); var left = n
            while (left > 0) { val r = input.read(b, 0, minOf(b.size, left)); if (r < 0) throw IOException("eof"); out.write(b, 0, r); left -= r }
        }

        private fun readLine(input: InputStream): String? {
            val sb = StringBuilder()
            while (true) {
                val c = input.read()
                if (c < 0) return if (sb.isEmpty()) null else sb.toString()
                if (c == '\n'.code) return sb.toString().trimEnd('\r')
                sb.append(c.toChar())
            }
        }

        private fun proxy(name: String, o: JsonObject): Proxy {
            val hist = (o["history"] as? JsonArray)?.lastOrNull()?.jsonObject
            return Proxy(
                name = name,
                type = o["type"]?.jsonPrimitive?.contentOrNull ?: "",
                now = o["now"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() },
                all = (o["all"] as? JsonArray)?.map { it.jsonPrimitive.content }.orEmpty(),
                lastDelay = hist?.get("delay")?.jsonPrimitive?.intOrNull,
                lastTestAt = hist?.get("time")?.jsonPrimitive?.contentOrNull?.let(::isoMillis),
            )
        }

        private fun conn(o: JsonObject): Conn0 {
            val m = o["metadata"]?.jsonObject ?: JsonObject(emptyMap())
            fun s(e: JsonElement?) = (e as? JsonPrimitive)?.contentOrNull.orEmpty()
            return Conn0(
                id = s(o["id"]),
                host = s(m["host"]).ifEmpty { s(m["sniffHost"]) }.ifEmpty { s(m["destinationIP"]) },
                process = s(m["process"]).ifEmpty { null },
                chains = (o["chains"] as? JsonArray)?.map { it.jsonPrimitive.content }.orEmpty(),
                rule = s(o["rule"]), rulePayload = s(o["rulePayload"]),
                up = (o["upload"] as? JsonPrimitive)?.longOrNull ?: 0, down = (o["download"] as? JsonPrimitive)?.longOrNull ?: 0,
                startMillis = isoMillis(s(o["start"])) ?: 0,
            )
        }

        internal fun isoMillis(s: String): Long? = runCatching { java.time.OffsetDateTime.parse(s).toInstant().toEpochMilli() }.getOrNull()

        /** mihomo rule type names → the Clash spelling users read in profiles. */
        fun ruleText(rule: String, payload: String): String {
            val t = when (rule) {
                "DomainSuffix" -> "DOMAIN-SUFFIX"; "Domain" -> "DOMAIN"; "DomainKeyword" -> "DOMAIN-KEYWORD"; "DomainRegex" -> "DOMAIN-REGEX"
                "GeoSite" -> "GEOSITE"; "GeoIP" -> "GEOIP"; "IPCIDR" -> "IP-CIDR"; "IPCIDR6" -> "IP-CIDR6"; "SrcIPCIDR" -> "SRC-IP-CIDR"
                "IPASN" -> "IP-ASN"; "RuleSet" -> "RULE-SET"; "Match" -> "MATCH"; "ProcessName" -> "PROCESS-NAME"; "ProcessPath" -> "PROCESS-PATH"
                "DstPort" -> "DST-PORT"; "SrcPort" -> "SRC-PORT"; "Network" -> "NETWORK"; "AND" -> "AND"; "OR" -> "OR"; "NOT" -> "NOT"
                else -> rule.uppercase()
            }
            return if (payload.isEmpty() || t == "MATCH") t else "$t,$payload"
        }

        val GROUP_TYPES = setOf("Selector", "URLTest", "Fallback", "LoadBalance", "Relay")
        private val BUILTIN = setOf("DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL")
        fun isBuiltin(name: String) = name in BUILTIN

        /** Region code from a node name (the Rust core does this for the library; live groups are small). */
        fun regionOf(name: String): String {
            val n = name.uppercase()
            for ((code, keys) in REGION_KEYS) if (keys.any { k -> if (k.length <= 2) Regex("(^|[^A-Z])$k([^A-Z]|$)").containsMatchIn(n) else n.contains(k) }) return code
            return "UN"
        }

        private val REGION_KEYS = listOf(
            "HK" to listOf("香港", "HK", "HONG KONG", "🇭🇰"), "TW" to listOf("台湾", "台灣", "TW", "TAIWAN", "🇹🇼"),
            "JP" to listOf("日本", "东京", "大阪", "JP", "JAPAN", "TOKYO", "🇯🇵"), "SG" to listOf("新加坡", "狮城", "SG", "SINGAPORE", "🇸🇬"),
            "US" to listOf("美国", "洛杉矶", "圣何塞", "US", "USA", "UNITED STATES", "🇺🇸"), "KR" to listOf("韩国", "首尔", "KR", "KOREA", "🇰🇷"),
            "GB" to listOf("英国", "伦敦", "UK", "GB", "UNITED KINGDOM", "🇬🇧"), "DE" to listOf("德国", "法兰克福", "DE", "GERMANY", "🇩🇪"),
            "FR" to listOf("法国", "FR", "FRANCE", "🇫🇷"), "CA" to listOf("加拿大", "CA", "CANADA", "🇨🇦"), "AU" to listOf("澳大利亚", "澳洲", "AU", "AUSTRALIA", "🇦🇺"),
            "IN" to listOf("印度", "IN", "INDIA", "🇮🇳"), "TR" to listOf("土耳其", "TR", "TURKEY", "🇹🇷"), "RU" to listOf("俄罗斯", "RU", "RUSSIA", "🇷🇺"),
            "NL" to listOf("荷兰", "NL", "NETHERLANDS", "🇳🇱"),
        )

        /** Stable negative id for a live (name-addressed) member, disjoint from the core's non-negative ids. */
        fun idOf(name: String): Long {
            var h = -0x340d631b7bdddcdbL
            for (ch in name) { h = h xor ch.code.toLong(); h *= 0x100000001b3L }
            return -((h ushr 2) + 1)
        }
    }
}
