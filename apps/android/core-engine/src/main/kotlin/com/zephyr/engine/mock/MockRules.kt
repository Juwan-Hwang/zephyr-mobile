package com.zephyr.engine.mock

import com.zephyr.engine.LayerKind
import com.zephyr.engine.RuleLayer

/** Rule layers and the prototype's `matchRule` (contract/mock-spec.md §4). */
internal object MockRules {

    val LAYERS: List<RuleLayer> = listOf(
        RuleLayer(0, LayerKind.OVERRIDE, "Zephyr 覆写", 14, "在订阅之上"),
        RuleLayer(1, LayerKind.SUBSCRIPTION, "Nebula Cloud", 1_284, "订阅规则"),
        RuleLayer(2, LayerKind.DOMAIN, "OpenAI", 312, "规则集 · 每天更新"),
        RuleLayer(3, LayerKind.DOMAIN, "广告与跟踪", 61_204_113, "规则集 · 每天更新"),
        RuleLayer(4, LayerKind.DOMAIN, "威胁情报", 33_481_790, "规则集 · 每小时更新"),
        RuleLayer(5, LayerKind.DOMAIN, "geosite:cn", 8_912_004, "规则集 · 每周更新"),
        RuleLayer(6, LayerKind.IP, "geoip:cn", 7_214, "规则集 · 每周更新"),
    )
    val TOTAL: Long = LAYERS.sumOf { it.count }
    const val DISK_BYTES: Long = 1_900_000_000L

    class Hit(val layer: Int, val rule: String, val ruleNo: Long, val policy: String)

    private val IPV4 = Regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$")
    private val IPV6 = Regex("^[0-9a-f:]+$")
    private val KW = Regex("doubleclick|adservice|ads?|tracker|analytics")

    private class Row(val layer: Int, val re: Regex, val rule: (String) -> String, val no: Long, val policy: String)

    private fun lastTwo(q: String) = q.split('.').takeLast(2).joinToString(".")

    private val TABLE = listOf(
        Row(0, Regex("(^|\\.)github\\.com$"), { "DOMAIN-SUFFIX,github.com" }, 2, "DIRECT"),
        Row(1, Regex("(^|\\.)netflix\\.com$|(^|\\.)nflxvideo\\.net$"), { "DOMAIN-SUFFIX,netflix.com" }, 318, "V"),
        Row(2, Regex("(^|\\.)openai\\.com$|(^|\\.)chatgpt\\.com$|(^|\\.)claude\\.ai$|(^|\\.)anthropic\\.com$"), { "DOMAIN-SUFFIX," + lastTwo(it) }, 41, "AI"),
        Row(3, Regex("doubleclick|adservice|(^|\\.)ads?\\.|tracker|analytics"), { "DOMAIN-KEYWORD," + (KW.find(it)?.value ?: "ad") }, 18_204_451, "REJECT"),
        Row(4, Regex("malware|phish"), { "DOMAIN,$it" }, 2_201_833, "REJECT"),
        Row(5, Regex("(^|\\.)(baidu|qq|taobao|bilibili|weibo|jd)\\.com$|\\.cn$"), { "DOMAIN-SUFFIX," + lastTwo(it) }, 1_120_458, "DIRECT"),
        Row(
            6,
            Regex("^(1\\.0\\.|36\\.|58\\.|101\\.|110\\.|111\\.|112\\.|113\\.|114\\.|115\\.|116\\.|117\\.|118\\.|119\\.|120\\.|121\\.|122\\.|123\\.|124\\.|125\\.)"),
            { "IP-CIDR," + it.split('.').take(2).joinToString(".") + ".0.0/16" },
            3_302,
            "DIRECT",
        ),
    )

    fun normalise(input: String): String = input.trim().lowercase()

    fun isIp(q: String): Boolean = IPV4.matches(q) || (q.contains(':') && IPV6.matches(q))

    /** First matching row in layer order; domains never reach the IP layer and vice-versa. */
    fun match(q: String): Hit? {
        val ip = IPV4.matches(q)
        for (r in TABLE) {
            if (ip != (r.layer == 6)) continue
            if (r.re.containsMatchIn(q)) return Hit(r.layer, r.rule(q), r.no, r.policy)
        }
        return null
    }

    /** Prototype policy codes → scene ids. */
    fun sceneIdFor(policy: String): String? = when (policy) {
        "AI" -> "ai"
        "V" -> "video"
        "O" -> "other"
        else -> null
    }
}
