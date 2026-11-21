package com.zephyr.app.screenshot

import android.view.View
import android.widget.RemoteViews
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
        val v = try { rv.apply(ctx, host) } catch (e: RemoteViews.ActionException) {
            // layoutlib cannot run click wiring (PendingIntent responses); clicks draw nothing, so drop them and retry.
            diag("first apply failed", e)
            stripActions(rv) { it.javaClass.name.contains("Click", ignoreCase = true) || it.javaClass.name.contains("Response") || it.javaClass.name.contains("PendingIntent") }
            try { rv.apply(ctx, host) } catch (e2: Exception) { diag("apply without click actions failed", e2); throw e2 }
        }
        val d = ctx.resources.displayMetrics.density
        host.addView(v, FrameLayout.LayoutParams((size.width.value * d).toInt(), (size.height.value * d).toInt()))
        return host
    }

    /** Test-only: removes matching actions from [rv] and every RemoteViews nested in it (reflection; layoutlib has no hidden-API checks). */
    private fun stripActions(rv: RemoteViews, drop: (Any) -> Boolean) {
        val seen = java.util.IdentityHashMap<Any, Unit>()
        fun walk(o: Any?) {
            if (o == null || seen.put(o, Unit) != null) return
            when (o) {
                is RemoteViews -> {
                    var c: Class<*>? = o.javaClass
                    while (c != null && c != Any::class.java) {
                        for (f in c.declaredFields) {
                            if (java.lang.reflect.Modifier.isStatic(f.modifiers)) continue
                            f.isAccessible = true
                            val v = runCatching { f.get(o) }.getOrNull()
                            if (f.name == "mActions" && v is MutableList<*>) {
                                @Suppress("UNCHECKED_CAST") val l = v as MutableList<Any?>
                                val removed = l.filter { it != null && drop(it) }
                                if (removed.isNotEmpty()) diagText("dropped: " + removed.joinToString { it!!.javaClass.name })
                                l.removeAll { it != null && drop(it) }
                                l.forEach { walkAction(it, ::walk) }
                            } else if (v is RemoteViews) walk(v)
                            else if (v is Iterable<*>) v.forEach { if (it is RemoteViews) walk(it) }
                            else if (v is Map<*, *>) v.values.forEach { if (it is RemoteViews) walk(it) }
                        }
                        c = c.superclass
                    }
                }
            }
        }
        walk(rv)
    }

    private fun walkAction(a: Any?, walk: (Any?) -> Unit) {
        if (a == null) return
        var c: Class<*>? = a.javaClass
        while (c != null && c != Any::class.java) {
            for (f in c.declaredFields) {
                if (java.lang.reflect.Modifier.isStatic(f.modifiers)) continue
                f.isAccessible = true
                val v = runCatching { f.get(a) }.getOrNull()
                if (v is RemoteViews) walk(v) else if (v is Iterable<*>) v.forEach { if (it is RemoteViews) walk(it) }
            }
            c = c.superclass
        }
    }

    /** Diagnostics land next to Paparazzi's failure images, which CI uploads as the paparazzi-failures artifact. */
    private fun diagText(s: String) {
        val d = java.io.File("build/paparazzi/failures").apply { mkdirs() }
        java.io.File(d, "widget-diag.txt").appendText("[dark=$dark] $s\n")
    }

    private fun diag(what: String, e: Throwable) {
        val sw = java.io.StringWriter(); e.printStackTrace(java.io.PrintWriter(sw)); diagText("$what\n$sw")
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
