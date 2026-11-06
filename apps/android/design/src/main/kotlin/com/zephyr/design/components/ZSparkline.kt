package com.zephyr.design.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/**
 * Smoothed traffic curve with a fading area fill (home hero). Monotone cubic interpolation so the line
 * never overshoots below zero. Path is rebuilt only when [values] changes (drawWithCache).
 */
@Composable
fun ZSparkline(
    values: List<Float>,
    modifier: Modifier = Modifier,
    color: Color = ZTheme.colors.download,
    fill: Boolean = true,
    strokeWidth: Float = 2.2f,
    description: String? = null,
) {
    Canvas(
        modifier
            .semantics { if (description != null) contentDescription = description }
            .drawWithCache {
                val n = values.size
                val line = Path()
                val area = Path()
                if (n >= 2) {
                    val max = (values.max()).coerceAtLeast(1e-3f) * 1.15f
                    val min = 0f
                    val w = size.width
                    val h = size.height
                    val dx = w / (n - 1)
                    val pts = Array(n) { i -> Offset(i * dx, h - (values[i] - min) / (max - min) * h * 0.92f) }
                    // monotone cubic tangents (Fritsch–Carlson)
                    val m = FloatArray(n)
                    val d = FloatArray(n - 1) { (pts[it + 1].y - pts[it].y) / dx }
                    m[0] = d[0]; m[n - 1] = d[n - 2]
                    for (i in 1 until n - 1) m[i] = if (d[i - 1] * d[i] <= 0) 0f else (d[i - 1] + d[i]) / 2
                    line.moveTo(pts[0].x, pts[0].y)
                    for (i in 0 until n - 1) {
                        val p0 = pts[i]; val p1 = pts[i + 1]
                        line.cubicTo(p0.x + dx / 3, p0.y + m[i] * dx / 3, p1.x - dx / 3, p1.y - m[i + 1] * dx / 3, p1.x, p1.y)
                    }
                    area.addPath(line)
                    area.lineTo(w, h); area.lineTo(0f, h); area.close()
                }
                val brush = Brush.verticalGradient(listOf(color.copy(alpha = 0.28f), color.copy(alpha = 0f)))
                val stroke = Stroke(width = strokeWidth.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
                onDrawBehind {
                    if (fill) drawPath(area, brush)
                    drawPath(line, color, style = stroke)
                }
            },
    ) {}
}

/** Convenience: keep the last [capacity] samples as floats for [ZSparkline]. */
class SparkBuffer(private val capacity: Int = 90) {
    private val data = ArrayDeque<Float>(capacity)
    fun push(v: Float): List<Float> { if (data.size == capacity) data.removeFirst(); data.addLast(v); return data.toList() }
    fun fill(vs: List<Float>): List<Float> { data.clear(); vs.takeLast(capacity).forEach { data.addLast(it) }; return data.toList() }
}

@Composable
fun rememberSparkBuffer(capacity: Int = 90) = remember { SparkBuffer(capacity) }
