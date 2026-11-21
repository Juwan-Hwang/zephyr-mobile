package com.zephyr.app.screenshot

import android.view.View
import android.widget.FrameLayout
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import com.zephyr.app.R
import com.zephyr.app.widget.ZephyrUsageWidget
import com.zephyr.app.widget.ZephyrWidget
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * And-8: home-screen widgets (Glance). Glance has no Compose UI tree, so the widget content is composed to
 * RemoteViews with [GlanceRemoteViews] (the same translation the launcher host gets), inflated with
 * RemoteViews.apply, and the resulting View is snapshotted. Data comes from the deterministic MockEngine.
 */
@OptIn(ExperimentalGlanceRemoteViewsApi::class)
@RunWith(Parameterized::class)
class WidgetScreenshotTest(private val dark: Boolean) {
    @get:Rule
    val zone = FixedZoneRule()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_9.copy(nightMode = if (dark) NightMode.NIGHT else NightMode.NOTNIGHT, locale = "zh"),
        maxPercentDifference = 0.1,
    )

    private lateinit var engine: MockEngine

    @Before fun setUp() {
        engine = MockEngine(clock = { HomeScreenshotTest.NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
    }

    private fun render(size: DpSize, content: @androidx.compose.runtime.Composable () -> Unit): View {
        val ctx = paparazzi.context
        val rv = runBlocking { GlanceRemoteViews().compose(ctx, size) { GlanceTheme { content() } }.remoteViews }
        val host = FrameLayout(ctx)
        val v = rv.apply(ctx, host)
        val d = ctx.resources.displayMetrics.density
        host.addView(v, FrameLayout.LayoutParams((size.width.value * d).toInt(), (size.height.value * d).toInt()))
        return host
    }

    private fun status(on: Boolean): Triple<String, String, Long> = runBlocking {
        val ctx = paparazzi.context
        val scenes = engine.scenes().first()
        val today = engine.usageToday().todayBytes
        if (on) Triple(ctx.getString(R.string.common_status_connected), "${ctx.getString(R.string.common_mode_rule)} · ${scenes.first().selected.name}", today)
        else Triple(ctx.getString(R.string.app_name), ctx.getString(R.string.common_status_disconnected), today)
    }

    @Test fun small() {
        val (title, detail, today) = status(on = true)
        val scenes = runBlocking { engine.scenes().first() }
        paparazzi.snapshot(render(ZephyrWidget.SMALL) { ZephyrWidget().Content(true, title, detail, today, scenes) })
    }

    @Test fun smallOff() {
        val (title, detail, today) = status(on = false)
        val scenes = runBlocking { engine.scenes().first() }
        paparazzi.snapshot(render(ZephyrWidget.SMALL) { ZephyrWidget().Content(false, title, detail, today, scenes) })
    }

    @Test fun medium() {
        val (title, detail, today) = status(on = true)
        val scenes = runBlocking { engine.scenes().first() }
        paparazzi.snapshot(render(ZephyrWidget.MEDIUM) { ZephyrWidget().Content(true, title, detail, today, scenes) })
    }

    @Test fun usage() {
        val u = runBlocking { engine.usageToday() }
        val hourly = u.hourly.let { h -> if (h.size >= 24) h.takeLast(24) else List(24 - h.size) { 0L } + h }
        paparazzi.snapshot(render(DpSize(170.dp, 170.dp)) { ZephyrUsageWidget().Content(u.todayBytes, hourly) })
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "dark={0}")
        fun params() = listOf(arrayOf<Any>(true), arrayOf<Any>(false))
    }
}
