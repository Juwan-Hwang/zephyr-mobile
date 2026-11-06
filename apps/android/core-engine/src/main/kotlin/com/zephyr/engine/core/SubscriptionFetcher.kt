package com.zephyr.engine.core

import java.net.HttpURLConnection
import java.net.URI

/**
 * Platform half of subscription import: HTTP only. Parsing, validation, storage, userinfo, redaction
 * and the node rebuild all live in core-mobile (`MobileCore.importSubscription`), shared with iOS.
 */
object SubscriptionFetcher {
    const val MAX_BYTES = 32 * 1024 * 1024

    data class Fetched(val body: String, val userInfo: String?, val fileName: String?)

        /** Content-Disposition: attachment; filename*=UTF-8''Nebula%20Cloud.yaml */
        fun dispositionName(h: String?): String? {
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
