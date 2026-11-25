package com.zephyr.design.components

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.ColorFilter
import com.zephyr.design.theme.ZTheme

/**
 * Hand-drawn 24-unit stroke icons (1.6 stroke), matching the prototype's SF-Symbol-like glyphs.
 * No Material icon dependency — keeps the APK small and both platforms visually identical.
 */
object ZIcons {
    /** [mirror]: a directional glyph (back, chevron, arrow) that flips in right-to-left layouts. */
    private fun stroke(name: String, vararg paths: String, width: Float = 1.6f, mirror: Boolean = false): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f, autoMirror = mirror).apply {
            paths.forEach {
                addPath(
                    pathData = addPathNodes(it),
                    stroke = SolidColor(Color.Black),
                    strokeLineWidth = width,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                )
            }
        }.build()

    private fun fill(name: String, vararg paths: String): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            paths.forEach { addPath(pathData = addPathNodes(it), fill = SolidColor(Color.Black)) }
        }.build()

    val Search = stroke("search", "M10.5 4a6.5 6.5 0 1 0 0 13a6.5 6.5 0 1 0 0-13z", "M15.5 15.5L20 20", width = 2f)
    /**
     * Issue #1 (real device): an 8-tooth gear. The prototype's sun (circle + rays) read as a light / dark toggle on
     * Home, not as 设置.
     */
    val Settings = stroke(
        "settings",
        "M18.81 10.37L21.12 10.78L21.12 13.22L18.81 13.63L17.97 15.66L19.31 17.58L17.58 19.31L15.66 17.97L13.63 18.81" +
            "L13.22 21.12L10.78 21.12L10.37 18.81L8.34 17.97L6.42 19.31L4.69 17.58L6.03 15.66L5.19 13.63L2.88 13.22" +
            "L2.88 10.78L5.19 10.37L6.03 8.34L4.69 6.42L6.42 4.69L8.34 6.03L10.37 5.19L10.78 2.88L13.22 2.88L13.63 5.19" +
            "L15.66 6.03L17.58 4.69L19.31 6.42L17.97 8.34z",
        "M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z",
    )
    val Grid = stroke(
        "grid",
        "M5.5 4h3a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-3A1.5 1.5 0 0 1 4 8.5v-3A1.5 1.5 0 0 1 5.5 4z",
        "M15.5 4h3a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-3A1.5 1.5 0 0 1 14 8.5v-3A1.5 1.5 0 0 1 15.5 4z",
        "M5.5 14h3a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-3A1.5 1.5 0 0 1 4 18.5v-3A1.5 1.5 0 0 1 5.5 14z",
        "M15.5 14h3a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-3a1.5 1.5 0 0 1-1.5-1.5v-3a1.5 1.5 0 0 1 1.5-1.5z",
        width = 1.8f,
    )
    /** Row affordance pointing toward the end edge (› in LTR, ‹ in RTL). */
    val ChevronRight = stroke("chevron_right", "M9.5 6l6 6l-6 6", width = 1.8f, mirror = true)
    val ChevronDown = stroke("chevron_down", "M7 10l5 5l5-5", width = 1.8f)
    val Back = stroke("back", "M15 4.5L7.5 12L15 19.5", width = 2.4f, mirror = true)
    val Close = stroke("close", "M6.5 6.5l11 11M17.5 6.5l-11 11", width = 1.8f)
    val Filter = stroke("filter", "M4 7h16M7 12h10M10 17h4", width = 2f)
    val Plus = stroke("plus", "M12 5v14M5 12h14", width = 2f)
    val ArrowDown = stroke("arrow_down", "M12 5v14M6.5 13.5L12 19l5.5-5.5", width = 2f)
    val ArrowUp = stroke("arrow_up", "M12 19V5M6.5 10.5L12 5l5.5 5.5", width = 2f)
    val ArrowRight = stroke("arrow_right", "M5 12h14M13.5 6.5L19 12l-5.5 5.5", width = 1.8f, mirror = true)
    val Check = stroke("check", "M5 12.5l4.5 4.5L19 7.5", width = 2.2f)
    val Qr = stroke(
        "qr",
        "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4z",
        "M14 14h2v2h-2zM18 14h2M14 18v2M18 18h2v2",
    )
    val Link = stroke("link", "M10 14a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 0 0-5.7-5.7L11.5 6.8", "M14 10a4 4 0 0 0-5.7 0l-2.8 2.8a4 4 0 0 0 5.7 5.7l1.3-1.3")
    val Laptop = stroke("laptop", "M5 6h14v9H5z", "M3 18h18")
    val File = stroke("file", "M7 3.5h7l4 4V20.5H7z", "M14 3.5v4h4")
    val Share = stroke("share", "M12 4v11M8 8l4-4l4 4", "M5 13v6h14v-6")
    val Lock = fill("lock", "M7 10V8a5 5 0 0 1 10 0v2h.5A1.5 1.5 0 0 1 19 11.5v8A1.5 1.5 0 0 1 17.5 21h-11A1.5 1.5 0 0 1 5 19.5v-8A1.5 1.5 0 0 1 6.5 10H7zm2 0h6V8a3 3 0 0 0-6 0v2z")
    val Bolt = fill("bolt", "M13 2L4.5 13.5H11L10 22l8.5-11.5H12L13 2z")
    val Globe = stroke("globe", "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z", "M3 12h18M12 3c2.5 2.7 3.6 5.7 3.6 9s-1.1 6.3-3.6 9M12 3c-2.5 2.7-3.6 5.7-3.6 9s1.1 6.3 3.6 9")
}

@Composable
fun ZIcon(icon: ImageVector, modifier: Modifier = Modifier, tint: Color = ZTheme.colors.text1, size: Dp = 22.dp, contentDescription: String? = null) {
    Image(
        painter = rememberVectorPainter(icon),
        contentDescription = contentDescription,
        modifier = modifier.size(size),
        colorFilter = ColorFilter.tint(tint),
    )
}
