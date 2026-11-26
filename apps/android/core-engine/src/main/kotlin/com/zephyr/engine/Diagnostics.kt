package com.zephyr.engine

/**
 * Contract §22.b: the collapsed 错误详情 shows engine text only after core `redactDiagnostic`. [fallbackRedact] is the
 * stand-in for engines without the native core (mock, screenshots, `.so` missing): same shape — whitespace folded,
 * every `http://` / `https://` URL reduced to scheme + host (credentials, path, query and token dropped), cut to
 * [MAX_CHARS] characters plus `…` — so raw subscription links never reach the screen even then.
 */
object Diagnostics {
    const val MAX_CHARS = 240

    private val URL = Regex("""https?://[^\s"'<>`）」，。]+""", RegexOption.IGNORE_CASE)

    fun fallbackRedact(text: String): String {
        val folded = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        val redacted = URL.replace(folded) { m -> redactUrl(m.value) }
        val n = redacted.codePointCount(0, redacted.length)
        if (n <= MAX_CHARS) return redacted
        return redacted.substring(0, redacted.offsetByCodePoints(0, MAX_CHARS)) + "…"
    }

    /** `https://user:pw@sub.example.com:8443/api?token=x` → `https://sub.example.com:8443/•••`. */
    internal fun redactUrl(url: String): String {
        val scheme = url.substringBefore("://")
        val rest = url.substringAfter("://")
        val authority = rest.substringBefore('/').substringBefore('?').substringBefore('#')
        val host = authority.substringAfterLast('@')
        val tail = rest.length > authority.length
        return "$scheme://$host" + if (tail || authority.contains('@')) "/•••" else ""
    }
}
