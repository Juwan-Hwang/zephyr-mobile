package com.zephyr.design.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/**
 * Smoothed traffic curve with a fading area fill (home hero). Samples are smoothed with a trailing mean and drawn
 * as a Catmull-Rom spline; the fill starts at α [FILL_ALPHA] and fades out at [FILL_FADE_AT] of the height (spec §9.8,
 * review And-2). Path is rebuilt only when [values] changes (drawWithCache).
 */
@Composable
fun ZSparkline(
    values: List<Float>,
    modifier: Modifier = Modifier,
    color: Color = ZTheme.colors.download,
    fill: Boolean = true,
    strokeWidth: Float = 2.2f,
    description: String? = null,
    /** Review H-P2-3: slide each new sample in over this many ms (0 = jump) and mark the newest point. */
    panMillis: Int = 0,
    headDot: Boolean = false,
) {
    val shift = remember { Animatable(0f) }
    if (panMillis > 0) LaunchedEffect(values) {
        // Start one step to the right and glide left; animation runs only while this is composed/visible.
        // Deliberately not mirrored in RTL: time runs left→right on charts in ar/fa/ur UIs too (the Canvas draws in
        // absolute coordinates), so the newest sample stays on the right edge.
        shift.snapTo(1f)
        shift.animateTo(0f, tween(panMillis, easing = LinearEasing))
    }
    Canvas(
        modifier
            .semantics { if (description != null) contentDescription = description }
            .drawWithCache {
                val n = values.size
                val line = Path()
                val area = Path()
                var head = Offset.Unspecified
                var step = 0f
                var fillTop = 0f
                if (n >= 2) {
                    // Review And-2 (spec §9.8): smooth, large swells like the prototype instead of per-second jitter.
                    // Trailing mean over SMOOTH_WINDOW samples: each point depends only on itself and older samples, so
                    // the already-drawn part of the curve does not wobble when a new sample arrives and pans in.
                    val smooth = FloatArray(n)
                    var acc = 0f
                    for (i in 0 until n) {
                        acc += values[i]
                        if (i >= SMOOTH_WINDOW) acc -= values[i - SMOOTH_WINDOW]
                        smooth[i] = acc / minOf(i + 1, SMOOTH_WINDOW)
                    }
                    val max = (smooth.max()).coerceAtLeast(1e-3f) * 1.15f
                    val w = size.width
                    val h = size.height
                    val dx = w / (n - 1)
                    val pts = Array(n) { i -> Offset(i * dx, h - smooth[i] / max * h * 0.92f) }
                    // Uniform Catmull-Rom as cubic Béziers (end points duplicated); control points clamped to the canvas
                    // so the curve never dips below the zero baseline or above the top.
                    fun cy(v: Float) = v.coerceIn(0f, h)
                    line.moveTo(pts[0].x, pts[0].y)
                    for (i in 0 until n - 1) {
                        val p0 = pts[maxOf(i - 1, 0)]; val p1 = pts[i]; val p2 = pts[i + 1]; val p3 = pts[minOf(i + 2, n - 1)]
                        line.cubicTo(
                            p1.x + (p2.x - p0.x) / 6f, cy(p1.y + (p2.y - p0.y) / 6f),
                            p2.x - (p3.x - p1.x) / 6f, cy(p2.y - (p3.y - p1.y) / 6f),
                            p2.x, p2.y,
                        )
                    }
                    head = pts[n - 1]; step = dx
                    fillTop = pts.minOf { it.y }
                    area.addPath(line)
                    area.lineTo(w, h); area.lineTo(0f, h); area.close()
                }
                // Fill ≈ α0.12 at the crest, fully faded by 60% of the height (spec §9.8).
                val fadeEnd = maxOf(size.height * FILL_FADE_AT, fillTop + 1f)
                val brush = Brush.verticalGradient(
                    listOf(color.copy(alpha = FILL_ALPHA), color.copy(alpha = 0f)),
                    startY = fillTop, endY = fadeEnd,
                )
                val stroke = Stroke(width = strokeWidth.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
                val dotR = 3.5.dp.toPx()
                onDrawBehind {
                    val tx = if (panMillis > 0) shift.value * step else 0f
                    clipRect {
                        translate(left = tx) {
                            if (fill) drawPath(area, brush)
                            drawPath(line, color, style = stroke)
                            if (headDot && head != Offset.Unspecified) drawCircle(color, dotR, head.copy(x = head.x - tx))
                        }
                    }
                }
            },
    ) {}
}

private const val SMOOTH_WINDOW = 6
private const val FILL_ALPHA = 0.12f
private const val FILL_FADE_AT = 0.6f

/** Convenience: keep the last [capacity] samples as floats for [ZSparkline]. */
class SparkBuffer(private val capacity: Int = 90) {
    private val data = ArrayDeque<Float>(capacity)
    fun push(v: Float): List<Float> { if (data.size == capacity) data.removeFirst(); data.addLast(v); return data.toList() }
    fun fill(vs: List<Float>): List<Float> { data.clear(); vs.takeLast(capacity).forEach { data.addLast(it) }; return data.toList() }
}

@Composable
fun rememberSparkBuffer(capacity: Int = 90) = remember { SparkBuffer(capacity) }
