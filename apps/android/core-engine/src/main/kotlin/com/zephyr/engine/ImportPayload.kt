package com.zephyr.engine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

// ── Contract §15: import payloads (desktop "同步到手机" QR, clash:// install links, bare links) ─────────────────

enum class ImportPayloadKind { ZEPHYR, CLASH_INSTALL, URL }

/** One subscription to import. [url] is the full http(s) link (never redacted; only handed to the fetcher). */
data class ImportItem(val name: String?, val url: String, val autoUpdateHours: Int?)

/** 1 ≤ items ≤ 20. */
data class ImportPayload(val kind: ImportPayloadKind, val items: List<ImportItem>)

/**
 * Why a payload was rejected. [category] matches the fixture's `err` (core MobileError Invalid / SubscriptionInvalid);
 * [message] is for logs only, never shown (contract §0.5). [versionTooNew] lets the UI say "update Zephyr" instead.
 */
class ImportPayloadException(val category: Category, message: String, val versionTooNew: Boolean = false) : Exception(message) {
    enum class Category(val wire: String) { INVALID("invalid"), SUBSCRIPTION_INVALID("subscription_invalid") }
}

/**
 * Kotlin twin of core-mobile `parse_import_payload` (contract §15). The real engine asks the core; MockEngine and the
 * UI pre-parse (multi-item confirmation, deep links) use this. Both are checked against
 * `contract/fixtures/import-payload-v1.json` case by case.
 *
 * Accepted (scheme/host case-insensitive, ≤ 4096 bytes, ≤ 20 items):
 * 1. `zephyr://import?url=<pct>&name=<pct>&auto=<h>`
 * 2. `zephyr://import?v=1&d=<base64url(JSON)>`, JSON = `{"v":1,"subs":[{"name","url","auto"}]}`
 * 3. `clash://` · `clashmeta://` · `mihomo://install-config?url=…&name=…`
 * 4. bare `http(s)://…`
 */
object ImportPayloads {
    const val MAX_ITEMS = 20
    const val MAX_PAYLOAD_BYTES = 4096
    private val CLASH = listOf("clash://install-config", "clashmeta://install-config", "mihomo://install-config")

    fun parse(payload: String): ImportPayload {
        val p = payload.trim()
        if (p.isEmpty()) invalid("empty payload")
        if (p.toByteArray(Charsets.UTF_8).size > MAX_PAYLOAD_BYTES) invalid("payload too long")
        val lower = p.lowercase(java.util.Locale.ROOT)
        val zq = query(p, lower, listOf("zephyr://import"))
        val cq = if (zq == null) query(p, lower, CLASH) else null
        val out = when {
            zq != null -> ImportPayload(ImportPayloadKind.ZEPHYR, zephyr(zq))
            cq != null -> ImportPayload(ImportPayloadKind.CLASH_INSTALL, listOf(item(pairs(cq))))
            lower.startsWith("http://") || lower.startsWith("https://") -> ImportPayload(ImportPayloadKind.URL, listOf(finish(null, p, null)))
            else -> invalid("not a subscription link or Zephyr import code")
        }
        if (out.items.isEmpty()) invalid("no subscriptions in payload")
        if (out.items.size > MAX_ITEMS) invalid("at most $MAX_ITEMS subscriptions at once")
        return out
    }

    /** Looks like a whole Clash / mihomo config pasted from the clipboard (imported as a local profile, like a file). */
    fun looksLikeConfig(payload: String): Boolean = payload.contains("proxies:") || payload.contains("proxy-providers:")

    /** Query string after one of [prefixes] (and an optional `/`), up to `#`; "" when nothing follows; null when no match. */
    private fun query(orig: String, lower: String, prefixes: List<String>): String? {
        for (pre in prefixes) {
            if (!lower.startsWith(pre)) continue
            var rest = orig.substring(pre.length)
            if (rest.startsWith("/")) rest = rest.substring(1)
            if (rest.isEmpty()) return ""
            if (!rest.startsWith("?")) return null
            return rest.substring(1).substringBefore('#')
        }
        return null
    }

    private fun pairs(q: String): List<Pair<String, String>> =
        q.split('&').filter { it.isNotEmpty() }.map { kv ->
            val i = kv.indexOf('=')
            if (i < 0) pct(kv) to "" else pct(kv.substring(0, i)) to pct(kv.substring(i + 1))
        }

    private fun List<Pair<String, String>>.get(key: String): String? = firstOrNull { it.first == key }?.second

    private fun zephyr(q: String): List<ImportItem> {
        val ps = pairs(q)
        ps.get("v")?.let { v -> if (v != "1") throw ImportPayloadException(ImportPayloadException.Category.INVALID, "import code v$v is too new", versionTooNew = true) }
        val d = ps.get("d") ?: return listOf(item(ps))
        val raw = base64Url(d) ?: invalid("import code data is damaged")
        val obj = runCatching { Json.parseToJsonElement(String(raw, Charsets.UTF_8)) as JsonObject }.getOrNull() ?: invalid("import code data is damaged")
        val v = runCatching { obj["v"]!!.jsonPrimitive.longOrNull }.getOrNull() ?: invalid("import code data is damaged")
        val subs = runCatching { obj["subs"]!!.jsonArray }.getOrNull() ?: invalid("import code data is damaged")
        if (v != 1L) throw ImportPayloadException(ImportPayloadException.Category.INVALID, "import code v$v is too new", versionTooNew = true)
        val parsed = subs.map { s ->
            val o = s as? JsonObject ?: invalid("import code data is damaged")
            val url = runCatching { o["url"]!!.jsonPrimitive.also { require(it.isString) }.content }.getOrNull() ?: invalid("import code data is damaged")
            val name = o["name"]?.let { n -> runCatching { n.jsonPrimitive.contentOrNull }.getOrNull() }
            val auto = o["auto"]?.let { a -> runCatching { a.jsonPrimitive }.getOrNull()?.let { p -> if (p.contentOrNull == null) null else p.intOrNull ?: invalid("import code data is damaged") } }
            Triple(name, url, auto)
        }
        return parsed.map { (n, u, a) -> finish(n, u, a) }
    }

    private fun item(ps: List<Pair<String, String>>): ImportItem {
        val url = ps.get("url") ?: invalid("missing url")
        val auto = ps.get("auto")?.takeIf { it.isNotEmpty() }?.let { it.toIntOrNull() ?: invalid("auto is not an integer") }
        return finish(ps.get("name"), url, auto)
    }

    private fun finish(name: String?, url: String, auto: Int?): ImportItem {
        val u = url.trim()
        validateUrl(u)
        val n = name?.trim()?.ifEmpty { null }
        if (n != null) validateName(n)
        if (auto != null && auto !in 0..720) invalid("auto out of range (0–720 hours)")
        return ImportItem(n, u, auto)
    }

    /** Desktop `validate_subscription_url_basic` essentials: http/https only, exactly `//` then a host, no control chars. */
    private fun validateUrl(url: String) {
        if (url.any { it.code < 0x20 || it.code == 0x7F }) subInvalid("Invalid URL: must not contain control characters")
        val lower = url.lowercase(java.util.Locale.ROOT)
        val rest = when {
            lower.startsWith("https://") -> lower.substring(8)
            lower.startsWith("http://") -> lower.substring(7)
            else -> subInvalid("Only HTTP and HTTPS URLs are allowed")
        }
        if (rest.isEmpty() || rest.startsWith("/") || rest.startsWith("\\")) subInvalid("URL must have a host")
        val host = runCatching { java.net.URI(url).host }.getOrNull()
            ?: rest.substringBefore('/').substringBefore('?').substringBefore('#').substringAfterLast('@').substringBefore(':')
        if (host.isBlank()) subInvalid("URL must have a host")
    }

    /** Desktop `validate_subscription_name` (→ sanitize_base_filename) essentials. */
    private fun validateName(n: String) {
        val t = n.trimEnd(' ', '.')
        if (t.contains('/') || t.contains('\\') || t == ".." || t == "." || t.isEmpty()) subInvalid("invalid subscription name")
        if (t.any { Character.isISOControl(it) }) subInvalid("invalid subscription name")
        if (t.toByteArray(Charsets.UTF_8).size > 255) subInvalid("subscription name too long")
    }

    /** Percent-decoding with `+` as space, like core; a bad escape or non-UTF-8 result is an error. */
    private fun pct(s: String): String {
        val b = s.toByteArray(Charsets.UTF_8)
        val out = java.io.ByteArrayOutputStream(b.size)
        var i = 0
        while (i < b.size) {
            when (val c = b[i].toInt()) {
                '%'.code -> {
                    if (i + 2 >= b.size) invalid("bad percent-encoding")
                    val v = String(b, i + 1, 2, Charsets.US_ASCII).toIntOrNull(16)?.takeIf { String(b, i + 1, 2, Charsets.US_ASCII).all { ch -> ch.isLetterOrDigit() } }
                        ?: invalid("bad percent-encoding")
                    out.write(v); i += 3
                }
                '+'.code -> { out.write(' '.code); i++ }
                else -> { out.write(c); i++ }
            }
        }
        val bytes = out.toByteArray()
        val dec = Charsets.UTF_8.newDecoder()
            .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
            .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
        return runCatching { dec.decode(java.nio.ByteBuffer.wrap(bytes)).toString() }.getOrElse { invalid("not UTF-8") }
    }

    private fun base64Url(s: String): ByteArray? {
        val t = s.trimEnd('=')
        if (!t.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' }) return null
        return runCatching { java.util.Base64.getUrlDecoder().decode(t) }.getOrNull()
    }

    private fun invalid(msg: String): Nothing = throw ImportPayloadException(ImportPayloadException.Category.INVALID, msg)
    private fun subInvalid(msg: String): Nothing = throw ImportPayloadException(ImportPayloadException.Category.SUBSCRIPTION_INVALID, msg)
}
