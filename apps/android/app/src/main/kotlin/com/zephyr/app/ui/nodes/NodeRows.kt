package com.zephyr.app.ui.nodes

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.zephyr.design.components.ZLatency
import com.zephyr.design.components.ZRegionBadge
import com.zephyr.design.components.ZSkeleton
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.RegionSection

/** Fixed 52dp node row: name (query terms highlighted, ×1.5 dimmed) · protocol · latency. */
@Composable
fun NodeRowView(n: NodeSummary?, highlights: List<String>, testedLatency: Int?, testing: Boolean) {
    val c = ZTheme.colors
    Row(Modifier.fillMaxWidth().height(52.dp).padding(start = 22.dp), verticalAlignment = Alignment.CenterVertically) {
        if (n == null) {
            ZSkeleton(Modifier.width(180.dp).height(14.dp))
            Spacer(Modifier.weight(1f))
            return@Row
        }
        val name = remember(n.name, highlights, c) { highlighted(n.name, highlights, c.accent, c.text3) }
        ZText(name, Modifier.weight(1f), style = ZTheme.type.body, maxLines = 1)
        ZText(n.protocol, style = ZTheme.type.monoSmall, color = c.text3, maxLines = 1)
        Spacer(Modifier.width(14.dp))
        ZLatency(testedLatency ?: n.latencyMs, testing, Modifier.width(64.dp), style = ZTheme.type.mono.copy(textAlign = androidx.compose.ui.text.style.TextAlign.End))
    }
    Box(Modifier.fillMaxWidth().padding(start = 22.dp).height(1.dp).background(c.hairline))
}

@Composable
fun SectionHeaderRow(s: RegionSection) {
    val c = ZTheme.colors
    Row(Modifier.fillMaxWidth().height(52.dp).padding(start = 22.dp), verticalAlignment = Alignment.CenterVertically) {
        ZRegionBadge(s.region)
        Spacer(Modifier.width(12.dp))
        ZText(s.name, Modifier.weight(1f), style = ZTheme.type.bodyStrong)
        ZText(ZFormat.grouped(s.count), style = ZTheme.type.mono, color = c.text3)
    }
}

private val MULT = Regex(" (×[\\d.]+)$")

private fun highlighted(name: String, terms: List<String>, accent: androidx.compose.ui.graphics.Color, dim: androidx.compose.ui.graphics.Color): AnnotatedString = buildAnnotatedString {
    val m = MULT.find(name)
    val base = if (m != null) name.substring(0, m.range.first) else name
    var i = 0
    val lower = base.lowercase()
    val hits = terms.mapNotNull { t -> val k = lower.indexOf(t.lowercase()); if (k >= 0 && t.isNotEmpty()) k until k + t.length else null }.sortedBy { it.first }
    for (r in hits) {
        if (r.first < i) continue
        append(base.substring(i, r.first))
        withStyle(SpanStyle(color = accent)) { append(base.substring(r.first, r.last + 1)) }
        i = r.last + 1
    }
    append(base.substring(i))
    if (m != null) withStyle(SpanStyle(color = dim, fontSize = androidx.compose.ui.unit.TextUnit.Unspecified)) { append(" "); append(m.groupValues[1]) }
}

fun Modifier.onSizeChangedCompat(block: (Int) -> Unit): Modifier = onSizeChanged { block(it.height) }
