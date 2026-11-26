package com.zephyr.app.widget

import com.zephyr.app.ui.common.sceneName
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
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
import com.zephyr.app.ui.common.labelRes
import com.zephyr.design.format.ZFormat
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.Scene
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.glance.layout.fillMaxHeight
import com.zephyr.app.MainActivity
import com.zephyr.app.R
import com.zephyr.engine.ProxyMode
import androidx.glance.ColorFilter
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.actionStartActivity


/**
 * Home-screen widget (prototype `hs`): small = status + mode/exit + today's usage; medium = + scene list.
 * Glance renders RemoteViews, so it reads a snapshot of engine state on each update (pushed by the VPN service on
 * connect/disconnect and once a minute while connected). It therefore shows nothing that changes every second: a
 * frozen "2.8 MB/s" was misleading for hours (review W-P1-1). Tapping the card opens the App; only the separate
 * power button connects/disconnects.
 */
class ZephyrWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, SMALL_TALL, MEDIUM_TALL, SMALL_XTALL, MEDIUM_XTALL))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        AppGraph.init(context)
        val first = load(context)
        provideContent {
            // Reloaded on every refreshAll(): provideGlance itself runs only once per Glance session (see WidgetRefresh).
            val tick by WidgetRefresh.tick.collectAsState()
            var s by remember { mutableStateOf(first) }
            LaunchedEffect(tick) { s = load(context) }
            GlanceTheme { Content(s.on, s.title, s.detail, s.today, s.scenes) }
        }
    }

    internal data class Snapshot(val on: Boolean, val title: String, val detail: String, val today: Long, val scenes: List<Scene>)

    private suspend fun load(context: Context): Snapshot {
        val e = AppGraph.engine
        val c = e.connectionState().first()
        val status = WidgetState.effectiveStatus(c.status, com.zephyr.app.vpn.ZephyrVpnService.running)
        val on = status == ConnectionStatus.CONNECTED
        val scenes = runCatching { e.scenes().first() }.getOrDefault(emptyList())
        // Live groups only while connected (the core is not running otherwise); a slow controller must not stall the card.
        val groups = if (on) withTimeoutOrNull(GROUPS_WAIT_MS) { runCatching { e.policyGroups().first() }.getOrNull() } ?: emptyList() else emptyList()
        val exits = WidgetState.sceneExits(scenes, groups)
        val today = runCatching { e.usageToday().todayBytes }.getOrDefault(0L)
        val global = if (c.mode == ProxyMode.GLOBAL) c.globalNodeId?.let { id -> runCatching { e.node(id).summary.name }.getOrNull() } else null
        val exit = WidgetState.exitFor(c.mode, global, exits, groups)
        val detail = when {
            status == ConnectionStatus.CONNECTING -> context.getString(R.string.common_status_connecting)
            !on -> context.getString(R.string.common_status_disconnected)
            else -> listOfNotNull(context.getString(c.mode.labelRes), exit).joinToString(" · ")
        }
        val title = if (on) context.getString(R.string.common_status_connected) else context.getString(R.string.app_name)
        return Snapshot(on, title, detail, today, exits)
    }

    @Composable
    internal fun Content(on: Boolean, title: String, detail: String, today: Long, scenes: List<Scene>) {
        val ctx = LocalContext.current
        val bg = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF141417))
        val t1 = ColorProvider(day = Color(0xE6000000), night = Color(0xF2FFFFFF))
        val t2 = ColorProvider(day = Color(0x94000000), night = Color(0x99FFFFFF))
        val t3 = ColorProvider(day = Color(0x8C000000), night = Color(0x80FFFFFF)) // tokens screen.t3: light 0.55 / dark 0.5 (WCAG AA, #37)
        val green = ColorProvider(day = Color(0xFF34C759), night = Color(0xFF30D158))
        val pwBg = ColorProvider(day = Color(0x0F000000), night = Color(0x1AFFFFFF))
        val accent = ColorProvider(day = Color(0xFF007AFF), night = Color(0xFF0A84FF))
        val wide = LocalSize.current.width >= MEDIUM.width
        // And-8: a 110 dp tall cell leaves ~86 dp for content, but power row + title + detail + 「今日」 need ~133 dp,
        // so RemoteViews clipped the last lines. Below TALL_MIN the card keeps power row + title + detail only
        // (tighter padding, 22sp title) and the scene column shows two rows; 「今日」 returns once the cell is tall enough.
        val compact = LocalSize.current.height < TALL_MIN
        // CodeAnt #285: at large system font sizes even the compact set overflows, so what shows is budgeted from
        // the cell height and the font scale (detail, then 「今日」, then scene rows drop first).
        val fit = widgetFit(LocalSize.current.height.value, ctx.resources.configuration.fontScale)
        val (tv, tu) = ZFormat.bytes(today)
        Row(
            GlanceModifier.fillMaxSize().background(bg).cornerRadius(24.dp).padding(if (compact) 12.dp else 16.dp).clickable(actionStartActivity<MainActivity>()),
        ) {
            // fillMaxHeight: the weighted spacer below only pushes title/detail down in a column as tall as the cell;
            // wrapping it left the lower half of a 4×2 card empty (S25 Ultra).
            Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
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
                            contentDescription = ctx.getString(if (on) R.string.common_disconnect else R.string.common_connect),
                            modifier = GlanceModifier.size(18.dp),
                            colorFilter = ColorFilter.tint(if (on) ColorProvider(day = Color.White, night = Color.White) else t1),
                        )
                    }
                }
                Spacer(GlanceModifier.defaultWeight())
                Text(title, style = TextStyle(color = t1, fontSize = if (compact) 22.sp else 24.sp), maxLines = 1)
                if (fit.detail) Text(detail, style = TextStyle(color = t2, fontSize = 12.sp), maxLines = 1)
                if (fit.today) {
                    Spacer(GlanceModifier.height(6.dp))
                    Text(ctx.getString(R.string.widget_today, tv, tu), style = TextStyle(color = t3, fontSize = 12.sp), maxLines = 1)
                }
            }
            // Scenes with an unknown exit are already left out (WidgetState.sceneExits); with none known the column hides.
            if (wide && scenes.isNotEmpty() && fit.sceneRows > 0) {
                Spacer(GlanceModifier.width(16.dp))
                Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
                    Text(ctx.getString(R.string.common_scenes), style = TextStyle(color = t3, fontSize = 12.sp))
                    // Rows spread over the cell height (8 dp minimum gap), the last one level with the left column's bottom line.
                    scenes.take(fit.sceneRows).forEach { s ->
                        Spacer(GlanceModifier.height(8.dp))
                        Spacer(GlanceModifier.defaultWeight())
                        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(ctx.resources.sceneName(s), style = TextStyle(color = t2, fontSize = 13.sp), modifier = GlanceModifier.width(40.dp))
                            Text(listOf(s.selected.region, s.selected.name).filter { it.isNotBlank() }.joinToString("  "), style = TextStyle(color = t1, fontSize = 13.sp), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                            // Review W-P2-3: prototype hs shows the scene's last measured latency ("61 ms"). It is a
                            // snapshot like everything else here, refreshed with the widget, never a live reading.
                            s.selected.latencyMs?.takeIf { it >= 0 }?.let { Text("$it ms", style = TextStyle(color = t3, fontSize = 12.sp), maxLines = 1) }
                        }
                    }
                }
            }
        }
    }

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(250.dp, 110.dp)
        val SMALL_TALL = DpSize(110.dp, 150.dp)
        val MEDIUM_TALL = DpSize(250.dp, 150.dp)
        /** 2 rows on large phones (S25 Ultra ≈ 190–220 dp): the fit budget uses the real height, not 150. */
        val SMALL_XTALL = DpSize(110.dp, 190.dp)
        val MEDIUM_XTALL = DpSize(250.dp, 190.dp)

        /** Live groups for the scene exits are a nicety; the card never waits longer than this for them. */
        private const val GROUPS_WAIT_MS = 1_500L

        /** Below this cell height the status card drops the 「今日」 line (content would clip). */
        val TALL_MIN = 140.dp

        /**
         * Which optional lines fit a status card [heightDp] tall at [fontScale]: power row 36 dp, then title, detail,
         * 「今日」 (only at ≥ [TALL_MIN]); scene column header + up to 3 rows. Text lines are budgeted at 1.4 × size × scale
         * (CJK fallback line height). At scale 1 this is exactly the 110 / 150 dp layouts in the snapshots.
         */
        internal fun widgetFit(heightDp: Float, fontScale: Float): WidgetFit {
            val compact = heightDp < TALL_MIN.value
            val avail = heightDp - 2 * (if (compact) 12f else 16f)
            fun line(sp: Float) = sp * 1.4f * fontScale
            val head = 36f + line(if (compact) 22f else 24f)
            val detail = head + line(12f) <= avail
            val today = !compact && detail && head + line(12f) + 6f + line(12f) <= avail
            val rows = ((avail - line(12f)) / (8f + line(13f))).toInt().coerceIn(0, 3)
            return WidgetFit(detail, today, rows)
        }

        /**
         * Redraws both widgets from the current state. Called on every connection change (connect, disconnect, fail,
         * pause, service destroyed or revoked, process start) and once a minute while connected.
         */
        suspend fun refreshAll(ctx: Context) {
            WidgetRefresh.bump()
            runCatching { ZephyrWidget().updateAll(ctx) }
            runCatching { ZephyrUsageWidget().updateAll(ctx) }
        }

        /** While connected the service refreshes at most this often (today's usage, scene exits); never per sample. */
        const val LIVE_REFRESH_MS = 60_000L
    }
}

internal data class WidgetFit(val detail: Boolean, val today: Boolean, val sceneRows: Int)

class ToggleAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        AppGraph.init(context)
        AppGraph.connection.toggle()
    }
}

class ZephyrWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ZephyrWidget()
}
