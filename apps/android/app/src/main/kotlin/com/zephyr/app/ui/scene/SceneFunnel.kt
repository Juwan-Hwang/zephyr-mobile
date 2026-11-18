package com.zephyr.app.ui.scene

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.ui.common.toPluralCount
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.NodeFunnel
import kotlin.math.ln
import kotlin.math.max

/** One funnel step: count and its label ("已测速"). */
data class FunnelStep(val count: Long, val label: String)

/** Contract §15.c steps: 全部 → 已测速 → 可连通 → 延迟低于 {threshold} ms (the per-service steps are not shown). */
@Composable
fun funnelSteps(f: NodeFunnel): List<FunnelStep> = listOf(
    FunnelStep(f.poolSize, stringResource(R.string.common_all)),
    FunnelStep(f.tested, stringResource(R.string.scene_funnel_tested)),
    FunnelStep(f.reachable, stringResource(R.string.scene_funnel_reachable)),
    FunnelStep(f.underThreshold, stringResource(R.string.scene_funnel_under, f.thresholdMs)),
)

/**
 * Scene funnel (prototype `.funnel`, 811–816; audit U11): one row per step, "count · bar · label", bar width on a
 * log scale of the largest step, the last step in the accent colour. Bars grow in from the leading edge one after
 * another (120 ms + 90 ms per step, prototype `openScene`); static when animations are off or in screenshots.
 */
@Composable
fun SceneFunnel(steps: List<FunnelStep>, modifier: Modifier = Modifier) {
    val c = ZTheme.colors
    val still = LocalInspectionMode.current || rememberAnimationsOff()
    val top = max(1L, steps.maxOfOrNull { it.count } ?: 1L)
    Column(modifier.fillMaxWidth().padding(horizontal = 22.dp)) {
        steps.forEachIndexed { i, s ->
            val last = i == steps.lastIndex
            val grow = remember(s.label) { Animatable(if (still) 1f else 0f) }
            LaunchedEffect(s.label) { if (!still) { kotlinx.coroutines.delay(120L + i * 90L); grow.animateTo(1f, tween(600, easing = ZAnim.EaseOut)) } }
            val a11y = "${s.label}, " + pluralStringResource(R.plurals.common_node_count, s.count.toPluralCount(), ZFormat.grouped(s.count))
            Row(
                Modifier.fillMaxWidth().heightIn(min = 30.dp).clearAndSetSemantics { contentDescription = a11y },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ZText(
                    ZFormat.grouped(s.count), Modifier.width(52.dp),
                    style = ZTheme.type.monoSmall.copy(textAlign = TextAlign.End), color = if (last) c.text1 else c.text2, maxLines = 1,
                )
                Spacer(Modifier.width(12.dp))
                Box(
                    Modifier.width(barWidth(s.count, top)).height(6.dp)
                        .graphicsLayer { scaleX = grow.value; transformOrigin = TransformOrigin(0f, 0.5f) }
                        .background(if (last) c.accent else c.surface4, ZTheme.shapes.pill),
                )
                Spacer(Modifier.width(12.dp))
                ZText(s.label, Modifier.weight(1f), style = ZTheme.type.footnote, color = if (last) c.text2 else c.text3, maxLines = 2)
            }
        }
    }
}

/** Log scale: 1 → 12 dp, the largest step → 160 dp; squared so the prototype's 58 / 30 / 13 / 6 % feel holds. */
private fun barWidth(n: Long, top: Long): Dp {
    val minW = 12f; val maxW = 160f
    if (top <= 1L) return maxW.dp
    val t = (ln(max(n, 1L).toDouble()) / ln(top.toDouble())).toFloat().coerceIn(0f, 1f)
    return (minW + (maxW - minW) * t * t).dp
}

@Composable
private fun rememberAnimationsOff(): Boolean {
    val ctx = LocalContext.current
    return remember { android.provider.Settings.Global.getFloat(ctx.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}
