package com.zephyr.app.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeFunnel
import kotlin.math.log10

/**
 * J-1 home mini funnel (spec §9.3; same drawing as iOS MiniFunnel): 全部 → 已测速 → 可连通 → 低于 200 ms as four
 * 3 dp bars in a row, widths log10(count + 1) normalised to [MINI_FUNNEL_WIDTH] so they shrink left to right (10⁷ and 9
 * both stay visible); first three t3, the last accent base with `underThreshold` under it (caption, t1, tabular).
 * Data comes from the row's own `sceneFunnel` (contract v0.7 §19.a); callers draw it only when counted.
 */
@Composable
fun MiniFunnel(f: NodeFunnel, modifier: Modifier = Modifier) {
    val c = ZTheme.colors
    val w = miniFunnelWidths(f)
    val lastX = w.dropLast(1).sum() + MINI_FUNNEL_GAP * (w.size - 1)
    val spoken = stringResource(R.string.home_mini_funnel_a11y, ZFormat.grouped(f.reachable), ZFormat.grouped(f.underThreshold))
    Column(modifier.width(MINI_FUNNEL_WIDTH.dp).clearAndSetSemantics { contentDescription = spoken }) {
        Row(horizontalArrangement = Arrangement.spacedBy(MINI_FUNNEL_GAP.dp)) {
            w.forEachIndexed { i, wi ->
                Box(Modifier.width(wi.dp).height(MINI_FUNNEL_BAR.dp).background(if (i == w.lastIndex) c.accent else c.text3, RoundedCornerShape((MINI_FUNNEL_BAR / 2).dp)))
            }
        }
        ZText(
            ZFormat.grouped(f.underThreshold),
            Modifier.padding(start = lastX.dp, top = 4.dp),
            style = ZTheme.type.caption.copy(fontFeatureSettings = "tnum"),
            color = c.text1,
            maxLines = 1,
        )
    }
}

/** Four bar widths in dp: log10(count + 1) shares of the room left after gaps, each at least [minimum] so a 0 still shows. */
internal fun miniFunnelWidths(f: NodeFunnel, total: Float = MINI_FUNNEL_WIDTH, gap: Float = MINI_FUNNEL_GAP, minimum: Float = 2f): List<Float> {
    val logs = listOf(f.poolSize, f.tested, f.reachable, f.underThreshold).map { log10(it.coerceAtLeast(0).toDouble() + 1) }
    val sum = logs.sum()
    val room = total - gap * (logs.size - 1) - minimum * logs.size
    if (sum <= 0 || room <= 0) return List(logs.size) { minimum }
    return logs.map { minimum + room * (it / sum).toFloat() }
}

internal const val MINI_FUNNEL_WIDTH = 120f
internal const val MINI_FUNNEL_GAP = 2f
internal const val MINI_FUNNEL_BAR = 3f
