package com.zephyr.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
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
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.zephyr.app.di.AppGraph
import com.zephyr.design.format.ZFormat
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.Scene
import kotlinx.coroutines.flow.first
import com.zephyr.app.MainActivity
import com.zephyr.app.R
import com.zephyr.engine.ProxyMode
import androidx.glance.ColorFilter
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity

private val ProxyMode.widgetLabel: String get() = when (this) { ProxyMode.RULE -> "规则"; ProxyMode.GLOBAL -> "全局"; ProxyMode.DIRECT -> "直连" }

/**
 * Home-screen widget (prototype `hs`): small = status + mode/exit + today's usage; medium = + scene list.
 * Glance renders RemoteViews, so it reads a snapshot of engine state on each update (pushed by the VPN service on
 * connect/disconnect and once a minute while connected). It therefore shows nothing that changes every second: a
 * frozen "2.8 MB/s" was misleading for hours (review W-P1-1). Tapping the card opens the App; only the separate
 * power button connects/disconnects.
 */
class ZephyrWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        AppGraph.init(context)
        val e = AppGraph.engine
        val c = e.connectionState().first()
        val scenes = runCatching { e.scenes().first() }.getOrDefault(emptyList())
        val today = runCatching { e.usageToday().todayBytes }.getOrDefault(0L)
        val on = c.status == ConnectionStatus.CONNECTED
        val exit = when (c.mode) {
            ProxyMode.GLOBAL -> c.globalNodeId?.let { id -> runCatching { e.node(id).summary.name }.getOrNull() }
            ProxyMode.DIRECT -> null
            ProxyMode.RULE -> scenes.firstOrNull()?.selected?.name
        }
        val detail = when {
            c.status == ConnectionStatus.CONNECTING -> "连接中"
            !on -> "未连接"
            else -> listOfNotNull(c.mode.widgetLabel, exit).joinToString(" · ")
        }
        provideContent { GlanceTheme { Content(on, if (on) "已连接" else "Zephyr", detail, today, scenes) } }
    }

    @Composable
    private fun Content(on: Boolean, title: String, detail: String, today: Long, scenes: List<Scene>) {
        val bg = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF141417))
        val t1 = ColorProvider(day = Color(0xE6000000), night = Color(0xF2FFFFFF))
        val t2 = ColorProvider(day = Color(0x94000000), night = Color(0x99FFFFFF))
        val t3 = ColorProvider(day = Color(0x8C000000), night = Color(0x66FFFFFF)) // light 0.55 (tokens screen.t3, WCAG AA)
        val green = ColorProvider(day = Color(0xFF34C759), night = Color(0xFF30D158))
        val pwBg = ColorProvider(day = Color(0x0F000000), night = Color(0x1AFFFFFF))
        val accent = ColorProvider(day = Color(0xFF007AFF), night = Color(0xFF0A84FF))
        val wide = LocalSize.current.width >= MEDIUM.width
        val (tv, tu) = ZFormat.bytes(today)
        Row(
            GlanceModifier.fillMaxSize().background(bg).cornerRadius(24.dp).padding(16.dp).clickable(actionStartActivity<MainActivity>()),
        ) {
            Column(GlanceModifier.defaultWeight()) {
                Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Box(GlanceModifier.size(8.dp).cornerRadius(4.dp).background(if (on) green else t3)) {}
                    Spacer(GlanceModifier.width(6.dp))
                    // 110 dp small widget: dot + power button leave no room for the wordmark; the title row says it.
                    if (wide) Text("Zephyr", style = TextStyle(color = t2, fontSize = 13.sp, fontWeight = FontWeight.Medium), modifier = GlanceModifier.defaultWeight())
                    else Spacer(GlanceModifier.defaultWeight())
                    // Prototype hs `.pw`: the only control that toggles the tunnel.
                    Box(
                        GlanceModifier.size(36.dp).cornerRadius(18.dp).background(if (on) accent else pwBg).clickable(actionRunCallback<ToggleAction>()),
                        contentAlignment = Alignment.Center,
                    ) {
                        Image(
                            ImageProvider(R.drawable.ic_widget_power),
                            contentDescription = if (on) "断开连接" else "连接",
                            modifier = GlanceModifier.size(18.dp),
                            colorFilter = ColorFilter.tint(if (on) ColorProvider(day = Color.White, night = Color.White) else t1),
                        )
                    }
                }
                Spacer(GlanceModifier.defaultWeight())
                Text(title, style = TextStyle(color = t1, fontSize = 24.sp), maxLines = 1)
                Text(detail, style = TextStyle(color = t2, fontSize = 12.sp), maxLines = 1)
                Spacer(GlanceModifier.height(6.dp))
                Text("今日 $tv $tu", style = TextStyle(color = t3, fontSize = 12.sp), maxLines = 1)
            }
            if (wide) {
                Spacer(GlanceModifier.width(16.dp))
                Column(GlanceModifier.defaultWeight()) {
                    Text("场景", style = TextStyle(color = t3, fontSize = 12.sp))
                    scenes.take(3).forEach { s ->
                        Spacer(GlanceModifier.height(8.dp))
                        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(s.name, style = TextStyle(color = t2, fontSize = 13.sp), modifier = GlanceModifier.width(40.dp))
                            Text("${s.selected.region}  ${s.selected.name}", style = TextStyle(color = t1, fontSize = 13.sp), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                            // Review W-P2-3: prototype hs shows the scene's last measured latency ("61 ms"). It is a
                            // snapshot like everything else here, refreshed with the widget, never a live reading.
                            s.selected.latencyMs?.let { Text("$it ms", style = TextStyle(color = t3, fontSize = 12.sp), maxLines = 1) }
                        }
                    }
                }
            }
        }
    }

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(250.dp, 110.dp)

        suspend fun refreshAll(ctx: Context) { runCatching { ZephyrWidget().updateAll(ctx) } }

        /** While connected the service refreshes at most this often (today's usage, scene exits); never per sample. */
        const val LIVE_REFRESH_MS = 60_000L
    }
}

class ToggleAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        AppGraph.init(context)
        AppGraph.connection.toggle()
    }
}

class ZephyrWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ZephyrWidget()
}
