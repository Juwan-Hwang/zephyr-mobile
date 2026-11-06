package com.zephyr.engine.mock

import com.zephyr.engine.RegionSection

/**
 * Index-only node query (port of prototype `buildModel`, contract/mock-spec.md §3).
 *
 * The query never scans nodes: each matched region is described by a period `P` and the
 * residues `S ⊂ [0, P)` that satisfy the filters, so counting and random access are O(|S|) and O(1).
 */
internal class NodeQuery private constructor(
    val query: String,
    val groups: List<Group>,
    val highlights: List<String>,
) {
    class Group(val region: Int, val count: Long, val residues: IntArray, val period: Int, val rowOffset: Long, val nodeOffset: Long)

    val total: Long = groups.sumOf { it.count }

    fun sections(): List<RegionSection> = groups.map {
        val g = MockCatalog.REGIONS[it.region]
        RegionSection(region = g.code, name = g.name, count = it.count, rowOffset = it.rowOffset)
    }

    /** Group holding the [ordinal]-th matched node (0-based, headers excluded). */
    fun groupForOrdinal(ordinal: Long): Int {
        var lo = 0
        var hi = groups.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) ushr 1
            if (groups[mid].nodeOffset <= ordinal) lo = mid else hi = mid - 1
        }
        return lo
    }

    /** Region index j of the k-th node inside [group]. */
    fun indexInRegion(group: Group, k: Long): Int {
        val s = group.residues.size
        return ((k / s) * group.period + group.residues[(k % s).toInt()]).toInt()
    }

    companion object {
        private val TYPING = Regex("^[a-z0-9+-]{1,3}$")
        private val WS = Regex("\\s+")

        fun build(raw: String): NodeQuery {
            val regions = MockCatalog.REGIONS
            val tokens = raw.trim().lowercase().split(WS).filter { it.isNotEmpty() }
            var regs: Set<Int>? = null
            val cityTok = HashMap<Int, Int>()
            val car = HashMap<Int, Int>()
            var tag: Int? = null
            var ok = true
            val hl = ArrayList<String>()
            fun meet(s: Set<Int>) { regs = regs?.intersect(s) ?: s }

            tokens.forEachIndexed { ti, tk ->
                val last = ti == tokens.lastIndex
                val s = LinkedHashSet<Int>()
                // a. region
                regions.forEachIndexed { ri, g ->
                    if (g.code.lowercase() == tk || g.name.contains(tk) || tk.contains(g.name)) s.add(ri)
                }
                if (s.isNotEmpty()) { meet(s); hl.add(tk); return@forEachIndexed }
                // b. city
                regions.forEachIndexed { ri, g ->
                    g.cities.forEachIndexed { ci, c ->
                        if (c.contains(tk) || tk.contains(c)) { s.add(ri); cityTok[ri] = ci; hl.add(c) }
                    }
                }
                if (s.isNotEmpty()) { meet(s); return@forEachIndexed }
                // c. carrier
                regions.forEachIndexed { ri, g ->
                    val ci = g.carriers.indexOfFirst { x ->
                        val l = x.lowercase()
                        l == tk || l.replace(WS, "") == tk || l.split(WS).contains(tk) || (tk.length >= 2 && l.startsWith(tk))
                    }
                    if (ci >= 0) { s.add(ri); car[ri] = ci; hl.add(g.carriers[ci]) }
                }
                if (s.isNotEmpty()) { meet(s); return@forEachIndexed }
                // d. tag
                val tIdx = MockCatalog.TAGS.indexOfFirst { x ->
                    val l = x.lowercase(); l == tk || (tk.length >= 2 && l.startsWith(tk))
                }
                if (tIdx >= 0) { tag = tIdx; hl.add(MockCatalog.TAGS[tIdx]); return@forEachIndexed }
                // e. still typing?
                if (last && TYPING.matches(tk)) return@forEachIndexed
                ok = false
            }

            val groups = ArrayList<Group>()
            if (ok) {
                var rowOffset = 0L
                var nodeOffset = 0L
                regions.forEachIndexed { ri, g ->
                    if (regs != null && ri !in regs!!) return@forEachIndexed
                    val l = g.cities.size
                    val c = g.carriers.size
                    val hasC = car.containsKey(ri)
                    val hasT = cityTok.containsKey(ri)
                    val p = ((if (hasT) l else 1) * (if (tag != null || hasC) 5 else 1) * (if (hasC) c else 1)).coerceAtLeast(1)
                    val res = ArrayList<Int>(p)
                    for (j in 0 until p) {
                        if (hasT && j % l != cityTok[ri]) continue
                        if (tag != null && MockCatalog.tagOf(ri, j) != tag) continue
                        if (hasC && MockCatalog.carOf(ri, j) != car[ri]) continue
                        res.add(j)
                    }
                    var cnt = 0L
                    for (s in res) if (s < g.count) cnt += (g.count - 1 - s) / p + 1
                    if (cnt > 0) {
                        groups.add(Group(ri, cnt, res.toIntArray(), p, rowOffset, nodeOffset))
                        rowOffset += 1 + cnt
                        nodeOffset += cnt
                    }
                }
            }
            return NodeQuery(raw, groups, hl)
        }
    }
}
