package com.zephyr.engine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * Contract §16.c (E42): settings decode field by field. A missing field, an unknown field, or one field with a bad
 * value (wrong type, unknown enum, null, out of range) falls back to that field's default only; the rest of the
 * stored settings is kept. Never resets the whole blob because one field failed.
 */
object SettingsCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val store = Json { ignoreUnknownKeys = true; encodeDefaults = false }

    fun encode(s: Settings): String = store.encodeToString(Settings.serializer(), s)

    fun decode(raw: String): Settings {
        val obj = runCatching { json.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return Settings()
        val defaults = json.encodeToJsonElement(Settings.serializer(), Settings()).jsonObject
        val merged = merge(defaults, obj) { candidate -> tryDecode(candidate) != null }
        return sanitized(tryDecode(merged) ?: Settings())
    }

    private fun tryDecode(o: JsonObject): Settings? = runCatching { json.decodeFromJsonElement(Settings.serializer(), o) }.getOrNull()

    /**
     * Starts from [defaults] and takes each field of [raw] that still decodes. Nested objects (dns, tun) are merged
     * the same way, so one bad `tun.mtu` keeps the stored `tun.ipv6`. [ok] decodes the whole candidate.
     */
    private fun merge(defaults: JsonObject, raw: JsonObject, ok: (JsonObject) -> Boolean): JsonObject {
        var acc = defaults
        for ((key, def) in defaults) {
            val v = raw[key] ?: continue
            if (def is JsonObject && v is JsonObject) {
                val nested = merge(def, v) { inner -> ok(JsonObject(acc + (key to inner))) }
                acc = JsonObject(acc + (key to nested))
                continue
            }
            val candidate = JsonObject(acc + (key to v))
            if (ok(candidate)) acc = candidate
        }
        return acc
    }

    // ── §16.c ranges and options ──────────────────────────────────────────────────────────────────────
    val LOCAL_PROXY_PORTS = 1024..65535
    val MTU_RANGE = 1280..9000
    val LATENCY_TTL_OPTIONS = listOf(6, 12, 24, 72)
    val AUTO_UPDATE_OPTIONS = listOf(6, 12, 24, 48)
    const val TRUSTED_WIFI_MAX = 50

    /** SSID: 1–32 bytes of UTF‑8 after trimming. */
    fun validSsid(name: String): Boolean = name.trim().toByteArray(Charsets.UTF_8).size in 1..32

    fun isValid(s: Settings): Boolean =
        s.localProxyPort in LOCAL_PROXY_PORTS && s.latencyTtlHours in LATENCY_TTL_OPTIONS && s.autoUpdateHours in AUTO_UPDATE_OPTIONS &&
            s.tun.mtu in MTU_RANGE && s.trustedWifi.size <= TRUSTED_WIFI_MAX && s.trustedWifi.all(::validSsid) && s.trustedWifi.distinct().size == s.trustedWifi.size

    /** Out-of-range values fall back to their own default (never the whole blob). */
    fun sanitized(s: Settings): Settings {
        val d = Settings()
        return s.copy(
            localProxyPort = s.localProxyPort.takeIf { it in LOCAL_PROXY_PORTS } ?: d.localProxyPort,
            latencyTtlHours = s.latencyTtlHours.takeIf { it in LATENCY_TTL_OPTIONS } ?: d.latencyTtlHours,
            autoUpdateHours = s.autoUpdateHours.takeIf { it in AUTO_UPDATE_OPTIONS } ?: d.autoUpdateHours,
            tun = s.tun.copy(mtu = s.tun.mtu.takeIf { it in MTU_RANGE } ?: d.tun.mtu),
            trustedWifi = s.trustedWifi.map { it.trim() }.filter(::validSsid).distinct().take(TRUSTED_WIFI_MAX),
        )
    }

}
