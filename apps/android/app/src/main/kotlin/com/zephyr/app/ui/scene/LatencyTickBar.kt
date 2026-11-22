package com.zephyr.app.ui.scene

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.design.tokens.ZLatency
import com.zephyr.engine.NodeId
import com.zephyr.engine.NodeSummary

/**
 * J-6 latency tick bar (spec §9.6, Halide style; same drawing as iOS LatencyTickBar), one line above the scene sheet's
 * candidate list:
 *
 *     200 ms
 *     ┊ ╷╷ ╷ ╷┃╷  ╷   ╷              超时 2
 *
 * Axis 0–600 ms linear (> 600 sticks to the right end); one 1×6 dp tick per measured candidate (t3, `screen.amber` at
 * ≥ 200 ms); the 200 ms tick is 1×12 dp t2 (`latency.threshold-slow`) with "200 ms" above it; the current exit's tick is
 * 10 dp in accent base and drawn last. Timeouts (latency < 0) are not drawn and count in the trailing 「超时 n」
 * (`screen.red-text`, hidden at 0); untested (null) is not drawn. The axis always runs left to right, also in RTL.
 */
@Composable
fun LatencyTickBar(candidates: List<NodeSummary>, selectedId: NodeId?, modifier: Modifier = Modifier) {
    val c = ZTheme.colors
    val stats = latencyTickStats(candidates)
    val spoken = stringResource(R.string.scene_tickbar_a11y, ZFormat.grouped(candidates.size.toLong()), ZFormat.grouped(stats.underThreshold.toLong()), ZFormat.grouped(stats.timeouts.toLong()))
    val caption = ZTheme.type.caption.copy(fontFeatureSettings = "tnum")
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(
            modifier.fillMaxWidth().height(TICKBAR_HEIGHT.dp).clearAndSetSemantics { contentDescription = spoken },
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            BoxWithConstraints(Modifier.weight(1f).height(TICKBAR_HEIGHT.dp)) {
                val w = maxWidth.value
                val x200 = tickX(ZLatency.slow, w)
                // "200 ms" centred over the long tick, kept inside the bar.
                ZText(
                    "${ZLatency.slow} ms",
                    Modifier.layout { m, k ->
                        val p = m.measure(k.copy(minWidth = 0))
                        val x = (x200.dp.roundToPx() - p.width / 2).coerceIn(0, (k.maxWidth - p.width).coerceAtLeast(0))
                        layout(k.maxWidth, p.height) { p.place(x, 0) }
                    },
                    style = caption, color = c.text3, maxLines = 1,
                )
                Canvas(Modifier.fillMaxWidth().height(LONG_TICK.dp).align(Alignment.BottomStart)) {
                    val h = size.height
                    val px = 1.dp.toPx()
                    fun tick(ms: Int, len: Float, color: androidx.compose.ui.graphics.Color) {
                        val x = tickX(ms, size.width / density) * density
                        val l = len.dp.toPx()
                        drawRect(color, Offset(x - px / 2, h - l), Size(px, l))
                    }
                    tick(ZLatency.slow, LONG_TICK, c.text2)
                    stats.measured.forEach { (id, ms) -> if (id != selectedId) tick(ms, SHORT_TICK, if (ms >= ZLatency.slow) c.warning else c.text3) }
                    stats.measured.firstOrNull { it.first == selectedId }?.let { (_, ms) -> tick(ms, SELECTED_TICK, c.accent) }
                }
            }
            if (stats.timeouts > 0) {
                ZText(stringResource(R.string.scene_tickbar_timeouts, ZFormat.grouped(stats.timeouts.toLong())), style = caption, color = c.dangerText, maxLines = 1)
            }
        }
    }
}

internal data class LatencyTickStats(val measured: List<Pair<NodeId, Int>>, val timeouts: Int, val underThreshold: Int)

/** Measured (≥ 0 ms) candidates, timeouts (< 0) and how many are under the 200 ms threshold; untested (null) count in none. */
internal fun latencyTickStats(candidates: List<NodeSummary>): LatencyTickStats {
    val measured = candidates.mapNotNull { n -> n.latencyMs?.takeIf { it >= 0 }?.let { n.id to it } }
    return LatencyTickStats(measured, candidates.count { (it.latencyMs ?: 0) < 0 }, measured.count { it.second < ZLatency.slow })
}

/** 0–600 ms mapped linearly onto [width] (0.5 dp kept at each end, > 600 ms sticks to the right end), in dp. */
internal fun tickX(ms: Int, width: Float): Float = 0.5f + (width - 1f) * (ms.coerceIn(0, TICKBAR_RANGE_MS) / TICKBAR_RANGE_MS.toFloat())

internal const val TICKBAR_RANGE_MS = 600
private const val SHORT_TICK = 6f
private const val SELECTED_TICK = 10f
private const val LONG_TICK = 12f
/** 12 dp tick area plus the "200 ms" line above it (iOS 30 pt). */
private const val TICKBAR_HEIGHT = 30
