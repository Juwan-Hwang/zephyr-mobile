package com.zephyr.engine.mock

import com.zephyr.engine.NodeSummary

/**
 * Deterministic node catalogue — a bit-exact port of design/prototype/pages.js (contract/mock-spec.md §1–2).
 *
 * Nothing is materialised: every node is a pure function of (region, index), so the full
 * 13,109,802-node library costs O(1) memory and O(1) per row.
 */
internal object MockCatalog {

    class Region(
        val code: String,
        val name: String,
        val count: Int,
        val cities: Array<String>,
        val baseLatency: Int,
        val carriers: Array<String>,
    ) {
        /** Period after which the `n` counter advances: lcm(cities, 5 * carriers). */
        val namePeriod: Int = lcm(cities.size, 5 * carriers.size)
    }

    val REGIONS: Array<Region> = arrayOf(
        Region("US", "美国", 3_118_402, arrayOf("洛杉矶", "圣何塞", "西雅图", "纽约", "达拉斯"), 152, arrayOf("CN2 GIA", "Cogent", "Zenlayer", "HE")),
        Region("JP", "日本", 2_204_117, arrayOf("东京", "大阪"), 58, arrayOf("NTT", "IIJ", "KDDI", "SoftBank")),
        Region("HK", "香港", 1_906_551, arrayOf("香港"), 34, arrayOf("HKT", "HKBN", "PCCW", "CMI")),
        Region("SG", "新加坡", 1_512_880, arrayOf("新加坡"), 63, arrayOf("Akari", "SingTel", "StarHub")),
        Region("TW", "台湾", 1_288_406, arrayOf("台北", "台中"), 41, arrayOf("HiNet", "Seednet", "So-net")),
        Region("KR", "韩国", 702_315, arrayOf("首尔", "春川"), 69, arrayOf("KT", "SK", "LG U+")),
        Region("DE", "德国", 488_210, arrayOf("法兰克福", "柏林"), 204, arrayOf("Hetzner", "DTAG")),
        Region("GB", "英国", 455_903, arrayOf("伦敦", "曼彻斯特"), 218, arrayOf("BT", "Vultr")),
        Region("NL", "荷兰", 301_442, arrayOf("阿姆斯特丹"), 226, arrayOf("KPN", "Leaseweb")),
        Region("FR", "法国", 254_118, arrayOf("巴黎"), 231, arrayOf("OVH", "Orange")),
        Region("CA", "加拿大", 239_770, arrayOf("多伦多", "温哥华"), 171, arrayOf("Bell", "Rogers")),
        Region("AU", "澳大利亚", 214_906, arrayOf("悉尼"), 139, arrayOf("Telstra", "Optus")),
        Region("IN", "印度", 198_331, arrayOf("孟买"), 118, arrayOf("Jio", "Airtel")),
        Region("BR", "巴西", 126_004, arrayOf("圣保罗"), 301, arrayOf("Vivo", "Claro")),
        Region("TR", "土耳其", 98_447, arrayOf("伊斯坦布尔"), 246, arrayOf("Türk Telekom")),
    )

    val TOTAL: Long = REGIONS.sumOf { it.count.toLong() }

    val TAGS = arrayOf("IPLC", "IEPL", "BGP", "家宽", "原生")
    val PROTOCOLS = arrayOf("VLESS", "Hy2", "TUIC", "SS", "Trojan")
    private val MULT_SUFFIX = arrayOf("", "", "", "", " ×1.5", "", "", " ×0.5", "", " ×2")
    private val MULT_VALUE = arrayOf(null, null, null, null, 1.5f, null, null, 0.5f, null, 2f)

    const val ID_STRIDE: Long = 100_000_000L

    /** 32-bit avalanche hash, returned as an unsigned value in a Long. */
    fun hsh(r: Int, j: Int): Long {
        var h = (j.toLong() * 2_654_435_761L + r.toLong() * 97L) and 0xFFFF_FFFFL
        h = h xor (h ushr 15)
        h = (h.toInt() * 2_246_822_519L.toInt()).toLong() and 0xFFFF_FFFFL // Math.imul
        h = h xor (h ushr 13)
        return h
    }

    fun tagOf(r: Int, j: Int): Int = ((j.toLong() * 7 + r) % 5).toInt()
    fun protOf(r: Int, j: Int): Int = (hsh(r + 7, j) % 5).toInt()
    fun carOf(r: Int, j: Int): Int = (j / 5) % REGIONS[r].carriers.size
    fun cityOf(r: Int, j: Int): Int = j % REGIONS[r].cities.size
    private fun multIndex(r: Int, j: Int): Int = (hsh(r + 3, j) % 10).toInt()

    fun nodeName(r: Int, j: Int): String {
        val g = REGIONS[r]
        val n = (j / g.namePeriod) % 64 + 1
        return buildString(24) {
            append(g.cities[cityOf(r, j)]).append(' ')
            append(g.carriers[carOf(r, j)]).append(' ')
            append(TAGS[tagOf(r, j)]).append(' ')
            if (n < 10) append('0')
            append(n)
            append(MULT_SUFFIX[multIndex(r, j)])
        }
    }

    /** Cached latency shown without testing (≈27% of nodes), or null. */
    fun cachedLatency(r: Int, j: Int): Int? {
        val h = hsh(r, j)
        return if (h % 11 < 3) REGIONS[r].baseLatency + (h % 37).toInt() else null
    }

    /** Result of an on-demand test: deterministic, ~4% timeouts. */
    fun testedLatency(r: Int, j: Int): Int {
        val h = hsh(r, j)
        return when {
            h % 23 == 0L -> -1
            else -> cachedLatency(r, j) ?: (REGIONS[r].baseLatency + (h % 37).toInt())
        }
    }

    fun idOf(r: Int, j: Int): Long = r * ID_STRIDE + j
    fun regionOf(id: Long): Int = (id / ID_STRIDE).toInt()
    fun indexOf(id: Long): Int = (id % ID_STRIDE).toInt()
    fun isValid(id: Long): Boolean {
        val r = regionOf(id)
        return id >= 0 && r in REGIONS.indices && indexOf(id) < REGIONS[r].count
    }

    fun summary(r: Int, j: Int, latencyOverride: Int? = null): NodeSummary {
        val g = REGIONS[r]
        return NodeSummary(
            id = idOf(r, j),
            name = nodeName(r, j),
            region = g.code,
            city = g.cities[cityOf(r, j)],
            carrier = g.carriers[carOf(r, j)],
            tag = TAGS[tagOf(r, j)],
            protocol = PROTOCOLS[protOf(r, j)],
            multiplier = MULT_VALUE[multIndex(r, j)],
            latencyMs = latencyOverride ?: cachedLatency(r, j),
        )
    }

    fun regionIndex(code: String): Int = REGIONS.indexOfFirst { it.code.equals(code, ignoreCase = true) }

    private tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)
    private fun lcm(a: Int, b: Int): Int = a / gcd(a, b) * b
}
