package com.zephyr.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
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
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        AppGraph.init(context)
        val u = runCatching { AppGraph.engine.usageToday() }.getOrNull()
        val today = u?.todayBytes ?: 0L
        val hourly = (u?.hourly ?: emptyList()).let { h -> if (h.size >= 24) h.takeLast(24) else List(24 - h.size) { 0L } + h }
        provideContent { GlanceTheme { Content(today, hourly) } }
    }

    @Composable
    private fun Content(today: Long, hourly: List<Long>) {
        val bg = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF141417))
        val t1 = ColorProvider(day = Color(0xE6000000), night = Color(0xF2FFFFFF))
        val t3 = ColorProvider(day = Color(0x8C000000), night = Color(0x80FFFFFF)) // tokens screen.t3 (#37)
        val accent = ColorProvider(day = Color(0xFF007AFF), night = Color(0xFF0A84FF))
        val idle = ColorProvider(day = Color(0x1F000000), night = Color(0x26FFFFFF))
        val (v, unit) = ZFormat.bytes(today)
        val peak = hourly.maxOrNull()?.takeIf { it > 0 } ?: 1L
        Column(
            GlanceModifier.fillMaxSize().background(bg).cornerRadius(24.dp).padding(16.dp).clickable(actionStartActivity<MainActivity>()),
        ) {
            Text(LocalContext.current.getString(R.string.common_today), style = TextStyle(color = t3, fontSize = 12.sp))
            Row(verticalAlignment = Alignment.Bottom) {
                Text(v, style = TextStyle(color = t1, fontSize = 28.sp, fontWeight = FontWeight.Normal), maxLines = 1)
                Spacer(GlanceModifier.width(4.dp))
                Text(unit, style = TextStyle(color = t3, fontSize = 13.sp), maxLines = 1)
            }
            Spacer(GlanceModifier.defaultWeight())
            Row(GlanceModifier.fillMaxWidth().height(BAR_MAX.dp), verticalAlignment = Alignment.Bottom) {
                hourly.forEachIndexed { i, b ->
                    if (i > 0) Spacer(GlanceModifier.width(2.dp))
                    val h = if (b <= 0) 2 else (BAR_MAX * b / peak).toInt().coerceIn(3, BAR_MAX)
                    Box(GlanceModifier.defaultWeight().height(h.dp).cornerRadius(1.5.dp).background(if (b > 0) accent else idle)) {}
                }
            }
        }
    }

    private companion object { const val BAR_MAX = 32 }
}

class ZephyrUsageWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ZephyrUsageWidget()
}
