package com.zephyr.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.zephyr.app.MainActivity
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.design.format.ZFormat

/**
 * Review W-P2-3: the prototype's second medium widget (hs) — today's usage with a 24-hour bar chart. A snapshot
 * refreshed with [ZephyrWidget.refreshAll]; bars are relative to the busiest hour, empty hours draw a 2dp stub.
 */
class ZephyrUsageWidget : GlanceAppWidget() {
    // And-8: re-render per cell height (default SizeMode.Single always laid out at the 250×110 minimum).
    override val sizeMode = SizeMode.Responsive(setOf(ZephyrWidget.MEDIUM, ZephyrWidget.MEDIUM_TALL))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        AppGraph.init(context)
        val first = load()
        provideContent {
            // Reloaded on every refreshAll(), not only when the Glance session starts (see WidgetRefresh).
            val tick by WidgetRefresh.tick.collectAsState()
            var s by remember { mutableStateOf(first) }
            LaunchedEffect(tick) { s = load() }
            GlanceTheme { Content(s.first, s.second) }
        }
    }

    private suspend fun load(): Pair<Long, List<Long>> {
        val u = runCatching { AppGraph.engine.usageToday() }.getOrNull()
        val today = u?.todayBytes ?: 0L
        val hourly = (u?.hourly ?: emptyList()).let { h -> if (h.size >= 24) h.takeLast(24) else List(24 - h.size) { 0L } + h }
        return today to hourly
    }

    @Composable
    internal fun Content(today: Long, hourly: List<Long>) {
        val bg = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF141417))
        val t1 = ColorProvider(day = Color(0xE6000000), night = Color(0xF2FFFFFF))
        val t3 = ColorProvider(day = Color(0x8C000000), night = Color(0x80FFFFFF)) // tokens screen.t3 (#37)
        val accent = ColorProvider(day = Color(0xFF007AFF), night = Color(0xFF0A84FF))
        val idle = ColorProvider(day = Color(0x1F000000), night = Color(0x26FFFFFF))
        val (v, unit) = ZFormat.bytes(today)
        val peak = hourly.maxOrNull()?.takeIf { it > 0 } ?: 1L
        // And-8: at the 110 dp minimum height 「今日」 + 28sp value + 32 dp bars + 32 dp padding ≈ 114 dp, so the bars
        // were clipped; below TALL_MIN the padding tightens and the bar height / 「今日」 line come from usageFit.
        val ctx = LocalContext.current
        val fit = usageFit(LocalSize.current.height.value, ctx.resources.configuration.fontScale)
        Column(
            GlanceModifier.fillMaxSize().background(bg).cornerRadius(24.dp).padding(fit.paddingDp.dp).clickable(actionStartActivity<MainActivity>()),
        ) {
            if (fit.label) Text(ctx.getString(R.string.common_today), style = TextStyle(color = t3, fontSize = 12.sp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text(v, style = TextStyle(color = t1, fontSize = 28.sp, fontWeight = FontWeight.Normal), maxLines = 1)
                Spacer(GlanceModifier.width(4.dp))
                Text(unit, style = TextStyle(color = t3, fontSize = 13.sp), maxLines = 1)
            }
            Spacer(GlanceModifier.defaultWeight())
            // Glance keeps at most 10 children per Row / Column (24 bars + 23 spacers were truncated to the first 5
            // bars), so the 24 hours are 4 groups × 6 bars, each bar padded 1 dp a side for the 2 dp gap.
            val barMax = fit.barMaxDp
            Row(GlanceModifier.fillMaxWidth().height(barMax.dp), verticalAlignment = Alignment.Bottom) {
                hourly.chunked(HOURS_PER_GROUP).forEach { group ->
                    Row(GlanceModifier.defaultWeight().fillMaxHeight(), verticalAlignment = Alignment.Bottom) {
                        group.forEach { b ->
                            val h = if (b <= 0) 2 else (barMax * b / peak).toInt().coerceIn(3, barMax)
                            Box(GlanceModifier.defaultWeight().fillMaxHeight().padding(horizontal = 1.dp), contentAlignment = Alignment.BottomCenter) {
                                Box(GlanceModifier.fillMaxWidth().height(h.dp).cornerRadius(1.5.dp).background(if (b > 0) accent else idle)) {}
                            }
                        }
                    }
                }
            }
        }
    }

    internal companion object {
        const val BAR_MAX = 32
        const val BAR_MIN = 12
        const val HOURS_PER_GROUP = 6

        /**
         * What fits a usage card [heightDp] tall at [fontScale]: padding 12 dp below [ZephyrWidget.TALL_MIN] (else 16),
         * the 28sp value always, 「今日」 only if bars keep ≥ 16 dp, and bars take the rest up to [BAR_MAX]. Text lines
         * are budgeted at 1.4 × size × scale like [ZephyrWidget.widgetFit].
         */
        internal fun usageFit(heightDp: Float, fontScale: Float): UsageFit {
            val pad = if (heightDp < ZephyrWidget.TALL_MIN.value) 12 else 16
            val avail = heightDp - 2 * pad
            fun line(sp: Float) = sp * 1.4f * fontScale
            val rest = avail - line(28f)
            val label = rest - line(12f) >= 16f
            val bars = (if (label) rest - line(12f) else rest).toInt().coerceIn(BAR_MIN, BAR_MAX)
            return UsageFit(pad, label, bars)
        }
    }
}

internal data class UsageFit(val paddingDp: Int, val label: Boolean, val barMaxDp: Int)

class ZephyrUsageWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ZephyrUsageWidget()
}
