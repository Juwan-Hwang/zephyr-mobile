package com.zephyr.app.ui.command

import com.zephyr.engine.AppInfo
import com.zephyr.engine.Apps
import com.zephyr.engine.SceneKind

/**
 * Prototype `parse()` (index.html ~1022): finds a service, a region and an action in free text.
 * Pure and synchronous so it can underline tokens on every keystroke (prototype `.tk.s/.r/.a`).
 */
object CommandParser {
    enum class Tok { SERVICE, REGION, ACTION }
    data class Span(val start: Int, val length: Int, val kind: Tok)
    data class Region(val name: String, val code: String)
    enum class Act(val label: String) { DIRECT("直连"), UHD("4K") }

    /** A service the user named: a built-in app, a scene word ("视频"), or an "其他" service with a host. */
    data class Service(val name: String, val kind: SceneKind, val app: AppInfo? = null, val host: String? = null) {
        val isSceneWord: Boolean get() = app == null && host == null
    }

    data class Parsed(val service: Service?, val region: Region?, val act: Act?, val spans: List<Span>) {
        val hasChips: Boolean get() = service != null || act != null
    }

    /** Prototype RGN plus the remaining regions of the node library. */
    private val REGIONS: List<Triple<String, String, List<String>>> = listOf(
        Triple("日本", "JP", listOf("日本", "东京", "大阪", "jp", "japan", "tokyo")),
        Triple("美国", "US", listOf("美国", "洛杉矶", "us", "usa")),
        Triple("香港", "HK", listOf("香港", "hk")),
        Triple("新加坡", "SG", listOf("新加坡", "狮城", "sg")),
        Triple("台湾", "TW", listOf("台湾", "台北", "tw")),
        Triple("英国", "GB", listOf("英国", "伦敦", "uk", "gb")),
        Triple("韩国", "KR", listOf("韩国", "首尔", "kr")),
        Triple("德国", "DE", listOf("德国", "法兰克福", "de")),
    )

    /** Prototype SVC rows for scene "其他": direct-able by host. */
    private val OTHER: List<Triple<String, String, List<String>>> = listOf(
        Triple("GitHub", "github.com", listOf("github")),
        Triple("Telegram", "telegram.org", listOf("telegram", "电报", "tg")),
    )

    private val ACTS = listOf(Act.DIRECT to listOf("直连", "不走代理", "direct"), Act.UHD to listOf("4k"))

    fun parse(q: String): Parsed {
        val lo = q.lowercase()
        val spans = ArrayList<Span>()
        var svc: Service? = null
        loop@ for (a in Apps.ALL) for (k in a.keywords) {
            val i = lo.indexOf(k)
            if (i >= 0) { svc = Service(a.name, a.kind, app = a); spans += Span(i, k.length, Tok.SERVICE); break@loop }
        }
        if (svc == null) loop@ for ((n, host, ks) in OTHER) for (k in ks) {
            val i = indexOfWord(lo, k)
            if (i >= 0) { svc = Service(n, SceneKind.OTHER, host = host); spans += Span(i, k.length, Tok.SERVICE); break@loop }
        }
        var rg: Region? = null
        loop@ for ((n, c, ks) in REGIONS) for (k in ks) {
            val i = indexOfWord(lo, k)
            if (i >= 0 && !overlaps(spans, i, k.length)) { rg = Region(n, c); spans += Span(i, k.length, Tok.REGION); break@loop }
        }
        var act: Act? = null
        loop@ for ((a, ks) in ACTS) for (k in ks) {
            val i = lo.indexOf(k)
            if (i >= 0) { act = a; spans += Span(i, k.length, Tok.ACTION); break@loop }
        }
        if (svc == null) {
            val m = Regex("视频|流媒体").find(q)
            if (m != null) { svc = Service("视频", SceneKind.VIDEO); spans += Span(m.range.first, m.value.length, Tok.SERVICE) }
        }
        return Parsed(svc, rg, act, spans.sortedBy { it.start })
    }

    /** Prototype rule: a ≤2-letter latin keyword must not sit inside a word ("us" in "status"). */
    private fun indexOfWord(lo: String, k: String): Int {
        var from = 0
        while (true) {
            val i = lo.indexOf(k, from)
            if (i < 0) return -1
            val short = k.length <= 2 && k.all { it in 'a'..'z' }
            val before = lo.getOrNull(i - 1); val after = lo.getOrNull(i + k.length)
            if (!short || ((before == null || before !in 'a'..'z') && (after == null || after !in 'a'..'z'))) return i
            from = i + 1
        }
    }

    private fun overlaps(spans: List<Span>, i: Int, len: Int) = spans.any { i < it.start + it.length && it.start < i + len }

    /** Prototype SUG: tapping one types it into the field (never runs an action). */
    val EXAMPLES = listOf("Gemini 走日本", "GitHub 直连", "视频只用 4K 节点", "香港")
}
