package com.zephyr.engine.core

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.Subscription
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URI

/**
 * On-disk subscription profiles (the real import path; MockEngine only fakes it).
 *
 * Layout under `<filesDir>/profiles/`:
 * - `index.json`   metadata for every subscription (what the UI lists)
 * - `<n>.yaml`     raw subscription YAML, n = core source id (1..65535)
 * - `active.yaml`  runtime config for mihomo: the selected profile after Zephyr core's
 *                  `prepareRuntimeConfig` (forced localhost controller + secret + safe defaults)
 * - `secret`       controller secret, regenerated whenever active.yaml is written
 *
 * Writes are atomic (tmp + rename) so a crash never leaves mihomo a half-written config.
 * Pure JVM + injectable [fetch]/[runtime] so it unit-tests without the native library.
 */
class ProfileStore(
    root: File,
    private val fetch: (String) -> Fetched = ::httpFetch,
    private val runtime: Runtime = Runtime.Native,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    data class Fetched(val body: String, val userInfo: String?, val fileName: String?)

    /** Seam over the UniFFI `zephyr_core` helpers (validated in CoreParityTest on the real .so). */
    interface Runtime {
        fun prepare(yaml: String, secret: String): String
        fun secret(): String
        object Native : Runtime {
            override fun prepare(yaml: String, secret: String): String =
                uniffi.zephyr_core.prepareRuntimeConfig(yaml, secret, null)?.yamlContent
                    ?: uniffi.zephyr_core.buildMinimalRuntimeConfig(secret).yamlContent
            override fun secret(): String = uniffi.zephyr_core.generateSecret()
        }
    }

    @Serializable
    internal data class Entry(
        val n: Int, val name: String, val url: String? = null, val nodeCount: Long = 0,
        val used: Long? = null, val total: Long? = null, val expire: Long? = null, val updatedAt: Long,
    )

    private val dir = File(root, "profiles").apply { mkdirs() }
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }
    private val entries = MutableStateFlow(load())
    private val _subs = MutableStateFlow(entries.value.map(::toSub))
    val subscriptions: StateFlow<List<Subscription>> = _subs.asStateFlow()
    val activeFile: File get() = File(dir, "active.yaml")

    /** All stored sources, for `MobileCore.rebuildNodes`. */
    fun sources(): List<Pair<Int, String>> = entries.value.mapNotNull { e -> File(dir, "${e.n}.yaml").takeIf { it.exists() }?.let { e.n to it.readText() } }

    /**
     * Imports a URL (fetched) or a raw YAML payload (file / clipboard text). Returns the new entry and
     * makes it the active profile when none is active yet. [count] receives the YAML and returns the
     * node count (the caller rebuilds the native node store and reports its total).
     */
    @Synchronized
    fun import(payload: String, isUrl: Boolean, count: (List<Pair<Int, String>>) -> Long): Subscription {
        val p = payload.trim()
        if (p.isEmpty()) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "empty")
        val got = if (isUrl) {
            if (!(p.startsWith("https://") || p.startsWith("http://"))) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "not a subscription link")
            runCatching { fetch(p) }.getOrElse { throw ZephyrException(ErrorCode.SUBSCRIPTION_FETCH_FAILED, it.message ?: "fetch failed") }
        } else Fetched(p, null, null)
        if (got.body.length > MAX_BYTES) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "too large")
        if (!looksLikeClash(got.body)) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "not a Clash/mihomo profile")

        val existing = entries.value.firstOrNull { isUrl && it.url == p }
        val n = existing?.n ?: ((entries.value.maxOfOrNull { it.n } ?: 0) + 1)
        if (n > 65_535) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "too many subscriptions")
        atomicWrite(File(dir, "$n.yaml"), got.body)
        val info = parseUserInfo(got.userInfo)
        val all = sources().filterNot { it.first == n } + (n to got.body)
        val nodes = runCatching { count(all) }.getOrDefault(0L)
        val e = Entry(
            n = n, name = existing?.name ?: nameFor(p, got.fileName, isUrl), url = if (isUrl) p else null,
            nodeCount = if (all.size == 1) nodes else countProxies(got.body), used = info.used, total = info.total,
            expire = info.expire, updatedAt = clock(),
        )
        commit(entries.value.filterNot { it.n == n } + e)
        if (!activeFile.exists() || existing != null) activate(n)
        return toSub(e)
    }

    @Synchronized
    fun delete(id: String) {
        val n = id.removePrefix("sub-").toIntOrNull() ?: throw ZephyrException(ErrorCode.SUBSCRIPTION_NOT_FOUND, id)
        if (entries.value.none { it.n == n }) throw ZephyrException(ErrorCode.SUBSCRIPTION_NOT_FOUND, id)
        File(dir, "$n.yaml").delete()
        commit(entries.value.filterNot { it.n == n })
        val first = entries.value.firstOrNull()
        if (first != null) activate(first.n) else { activeFile.delete(); File(dir, "secret").delete() }
    }

    /** Writes `active.yaml` for mihomo from profile [n]. */
    @Synchronized
    fun activate(n: Int) {
        val raw = File(dir, "$n.yaml").readText()
        val secret = runtime.secret()
        atomicWrite(activeFile, runtime.prepare(raw, secret))
        atomicWrite(File(dir, "secret"), secret)
    }

    private fun commit(list: List<Entry>) {
        atomicWrite(File(dir, "index.json"), json.encodeToString(ListSerializer(Entry.serializer()), list))
        entries.value = list
        _subs.value = list.map(::toSub)
    }

    private fun load(): List<Entry> = runCatching {
        json.decodeFromString(ListSerializer(Entry.serializer()), File(dir, "index.json").readText())
    }.getOrDefault(emptyList())

    private fun toSub(e: Entry) = Subscription(
        id = "sub-${e.n}", name = e.name, url = e.url?.let(::redact), nodeCount = e.nodeCount,
        usedBytes = e.used, totalBytes = e.total, remainingBytes = if (e.total != null && e.used != null) (e.total - e.used).coerceAtLeast(0) else null,
        expiresAt = e.expire, updatedAt = e.updatedAt,
    )

    companion object {
        const val MAX_BYTES = 32 * 1024 * 1024

        internal data class UserInfo(val used: Long?, val total: Long?, val expire: Long?)

        /** `subscription-userinfo: upload=1; download=2; total=3; expire=1700000000` (seconds). */
        internal fun parseUserInfo(h: String?): UserInfo {
            if (h.isNullOrBlank()) return UserInfo(null, null, null)
            val m = h.split(';').mapNotNull { kv -> kv.split('=', limit = 2).takeIf { it.size == 2 }?.let { it[0].trim().lowercase() to it[1].trim().toDoubleOrNull()?.toLong() } }.toMap()
            val up = m["upload"]; val down = m["download"]
            val used = if (up != null || down != null) (up ?: 0) + (down ?: 0) else null
            return UserInfo(used, m["total"]?.takeIf { it > 0 }, m["expire"]?.takeIf { it > 0 }?.times(1000))
        }

        internal fun looksLikeClash(y: String): Boolean {
            val head = y.lineSequence().take(4000).map { it.trimEnd() }
            return head.any { it.startsWith("proxies:") || it.startsWith("proxy-providers:") || it.startsWith("proxy-groups:") }
        }

        /** Cheap top-level `proxies:` item count, used for secondary profiles (the core counts the merged set). */
        internal fun countProxies(y: String): Long {
            var inside = false; var n = 0L
            for (raw in y.lineSequence()) {
                if (raw.isEmpty() || raw.trimStart().startsWith('#')) continue
                if (!raw[0].isWhitespace() && raw[0] != '-') { inside = raw.startsWith("proxies:"); if (inside && raw.contains('[')) return 0; continue }
                if (inside && raw.trimStart().startsWith("- ") && (raw.length - raw.trimStart().length) <= 2) n++
            }
            return n
        }

        internal fun nameFor(p: String, fileName: String?, isUrl: Boolean): String {
            fileName?.substringBeforeLast('.')?.takeIf { it.isNotBlank() }?.let { return it }
            if (!isUrl) return "本地配置"
            val host = runCatching { URI(p).host }.getOrNull() ?: return "新订阅"
            val parts = host.split('.').filter { it.isNotEmpty() }
            val core = if (parts.size >= 2) parts[parts.size - 2] else parts.firstOrNull() ?: "新订阅"
            return core.replaceFirstChar { it.uppercase() }
        }

        /** Never show tokens: keep scheme + host, mask path/query. */
        internal fun redact(url: String): String = runCatching {
            val u = URI(url); "${u.scheme}://${u.host}/…"
        }.getOrDefault("…")

        internal fun atomicWrite(f: File, text: String) {
            val tmp = File(f.parentFile, ".${f.name}.tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(f)) { f.delete(); check(tmp.renameTo(f)) { "rename ${f.name}" } }
        }

        /** Content-Disposition: attachment; filename*=UTF-8''Nebula%20Cloud.yaml */
        internal fun dispositionName(h: String?): String? {
            if (h == null) return null
            Regex("filename\\*=(?:UTF-8'')?([^;]+)", RegexOption.IGNORE_CASE).find(h)?.let { return java.net.URLDecoder.decode(it.groupValues[1].trim('"'), "UTF-8") }
            return Regex("filename=\"?([^\";]+)", RegexOption.IGNORE_CASE).find(h)?.groupValues?.get(1)
        }

        fun httpFetch(url: String): Fetched {
            var target = url
            repeat(5) {
                val c = (java.net.URL(target).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15_000; readTimeout = 30_000; instanceFollowRedirects = false
                    setRequestProperty("User-Agent", "clash.meta (Zephyr Android)")
                    setRequestProperty("Accept", "application/yaml, text/yaml, */*")
                }
                try {
                    val code = c.responseCode
                    if (code in 300..399) { target = URI(target).resolve(c.getHeaderField("Location") ?: error("redirect")).toString(); return@repeat }
                    if (code !in 200..299) error("HTTP $code")
                    if (c.contentLengthLong > MAX_BYTES) error("too large")
                    val body = c.inputStream.use { s ->
                        val buf = java.io.ByteArrayOutputStream(); val b = ByteArray(64 * 1024); var total = 0
                        while (true) { val r = s.read(b); if (r < 0) break; total += r; if (total > MAX_BYTES) error("too large"); buf.write(b, 0, r) }
                        buf.toString(Charsets.UTF_8.name())
                    }
                    return Fetched(body, c.getHeaderField("subscription-userinfo"), dispositionName(c.getHeaderField("Content-Disposition")))
                } finally { c.disconnect() }
            }
            error("too many redirects")
        }
    }
}
