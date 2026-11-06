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

/**
 * Home-screen widget (prototype `hs`): small = status + speed; medium = + scene list.
 * Glance renders RemoteViews, so it reads a snapshot of engine state on each update (pushed by the VPN service).
 */
class ZephyrWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        AppGraph.init(context)
        val e = AppGraph.engine
        val c = e.connectionState().first()
        val scenes = e.scenes().first()
        val today = e.usageToday()
        val sample = if (c.status == ConnectionStatus.CONNECTED) e.recentTraffic(1).lastOrNull() else null
        provideContent { GlanceTheme { Content(c.status == ConnectionStatus.CONNECTED, sample?.downBps ?: 0, today.todayBytes, scenes) } }
    }

    @Composable
    private fun Content(on: Boolean, down: Long, today: Long, scenes: List<Scene>) {
        val bg = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF141417))
        val t1 = ColorProvider(day = Color(0xE6000000), night = Color(0xF2FFFFFF))
        val t2 = ColorProvider(day = Color(0x94000000), night = Color(0x99FFFFFF))
        val t3 = ColorProvider(day = Color(0x66000000), night = Color(0x66FFFFFF))
        val green = ColorProvider(day = Color(0xFF34C759), night = Color(0xFF30D158))
        val wide = LocalSize.current.width >= MEDIUM.width
        val (dv, du) = ZFormat.rate(down)
        val (tv, tu) = ZFormat.bytes(today)
        Row(
            GlanceModifier.fillMaxSize().background(bg).cornerRadius(24.dp).padding(16.dp).clickable(actionRunCallback<ToggleAction>()),
        ) {
            Column(GlanceModifier.defaultWeight()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(GlanceModifier.size(8.dp).cornerRadius(4.dp).background(if (on) green else t3)) {}
                    Spacer(GlanceModifier.width(6.dp))
                    Text("Zephyr", style = TextStyle(color = t2, fontSize = 13.sp, fontWeight = FontWeight.Medium))
                }
                Spacer(GlanceModifier.defaultWeight())
                Text(if (on) dv else "—", style = TextStyle(color = t1, fontSize = 34.sp))
                Text(if (on) "$du/s · 规则" else "未连接", style = TextStyle(color = t2, fontSize = 12.sp))
                Spacer(GlanceModifier.height(6.dp))
                Text("今日 $tv $tu", style = TextStyle(color = t3, fontSize = 12.sp))
            }
            if (wide) {
                Spacer(GlanceModifier.width(16.dp))
                Column(GlanceModifier.defaultWeight()) {
                    Text("场景", style = TextStyle(color = t3, fontSize = 12.sp))
                    scenes.take(3).forEach { s ->
                        Spacer(GlanceModifier.height(8.dp))
                        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(s.name, style = TextStyle(color = t2, fontSize = 13.sp), modifier = GlanceModifier.width(40.dp))
                            Text("${s.selected.region}  ${s.selected.name}", style = TextStyle(color = t1, fontSize = 13.sp), maxLines = 1)
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
