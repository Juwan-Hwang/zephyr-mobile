package com.zephyr.app.screenshot

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import com.zephyr.app.ui.home.HomeActions
import com.zephyr.app.ui.home.HomeCallbacks
import com.zephyr.app.ui.home.HomeContent
import com.zephyr.app.ui.home.HomeUi
import com.zephyr.app.ui.home.HomeLive
import com.zephyr.design.theme.ZephyrTheme
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Home in the prototype's connected demo state across theme × accent × font scale (spec §9 acceptance matrix). */
@RunWith(Parameterized::class)
class HomeScreenshotTest(private val dark: Boolean, private val accent: ZAccent, private val fontScale: Float) {

    @get:Rule
    val zone = FixedZoneRule()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_9.copy(
            nightMode = if (dark) NightMode.NIGHT else NightMode.NOTNIGHT,
            fontScale = fontScale,
            // Baselines are the Chinese UI; English is the resource default, so pin the locale.
            locale = "zh",
        ),
        maxPercentDifference = 0.1,
    )

    @Test
    fun home() {
        val e = MockEngine(clock = { NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        val (conn, scenes, subs, usage, spark) = runBlocking {
            Quint(e.connectionState().first(), e.scenes().first(), e.subscriptions().first(), e.usageToday(), e.recentTraffic(90))
        }
        val ui = HomeUi(now = NOW, usage = usage, funnels = funnels(e, scenes))
        val live = HomeLive(traffic = spark.last(), spark = spark.map { it.downBps.toFloat() }, now = NOW)
        paparazzi.snapshot {
            ZephyrTheme(dark = dark, accent = accent) {
                HomeContent(conn, scenes, subs, ui, { live }, NO_ACTIONS, NO_CB, picker = picker(e, scenes))
            }
        }
    }

    @Test
    fun homeGlobal() {
        if (accent != ZAccent.BLUE || fontScale != 1f) return
        val e = MockEngine(clock = { NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        val (conn, scenes, subs, usage, spark) = runBlocking {
            e.setMode(ProxyMode.GLOBAL)
            Quint(e.connectionState().first(), e.scenes().first(), e.subscriptions().first(), e.usageToday(), e.recentTraffic(90))
        }
        // Only the name is drawn ("所有流量均经由东京 03"); the mock has no GLOBAL policy group.
        val global = com.zephyr.engine.NodeSummary(id = conn.globalNodeId ?: 0, name = "东京 03", region = "JP", protocol = "vless")
        val ui = HomeUi(now = NOW, usage = usage, globalNode = global)
        val live = HomeLive(traffic = spark.last(), spark = spark.map { it.downBps.toFloat() }, now = NOW)
        val picker = com.zephyr.app.ui.home.NodePickerUi(mode = ProxyMode.GLOBAL, label = global.name, latencyMs = 112)
        paparazzi.snapshot { ZephyrTheme(dark = dark, accent = accent) { HomeContent(conn, scenes, subs, ui, { live }, NO_ACTIONS, NO_CB, picker = picker) } }
    }

    /** Prototype 10 (scan): AI scene re-testing, header "正在检测 138/512", row bar at 27 %. */
    @Test
    fun homeScan() {
        if (accent != ZAccent.BLUE || fontScale != 1f) return
        val e = MockEngine(clock = { NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        val (conn, scenes, subs, usage, spark) = runBlocking {
            Quint(e.connectionState().first(), e.scenes().first(), e.subscriptions().first(), e.usageToday(), e.recentTraffic(90))
        }
        val ai = scenes.first { it.kind == com.zephyr.engine.SceneKind.AI }.id
        val ui = HomeUi(now = NOW, usage = usage, funnels = funnels(e, scenes))
        val live = HomeLive(traffic = spark.last(), spark = spark.map { it.downBps.toFloat() }, now = NOW)
        paparazzi.snapshot {
            ZephyrTheme(dark = dark, accent = accent) {
                HomeContent(conn, scenes, subs, ui, { live }, NO_ACTIONS, NO_CB, retesting = setOf(ai), scan = com.zephyr.engine.ScanProgress(138, 512), picker = picker(e, scenes))
            }
        }
    }

    private data class Quint<A, B, C, D, E>(val a: A, val b: B, val c: C, val d: D, val e: E)

    companion object {
        /** J-1: each row's mini funnel as the home view model loads it (sceneFunnel, 24 h window, 200 ms). */
        fun funnels(e: com.zephyr.engine.ZephyrEngine, scenes: List<com.zephyr.engine.Scene>): Map<String, com.zephyr.engine.NodeFunnel> = runBlocking {
            scenes.filter { it.source != com.zephyr.engine.SceneSource.SUBSCRIPTION_GROUP }
                .mapNotNull { s -> e.sceneFunnel(s.id, 24 * 3_600_000L, 200)?.takeIf { it.poolSize > 0 }?.let { s.id to it } }.toMap()
        }

        /** 2026-11-06 09:41 CST, the prototype's status-bar time. */
        const val NOW = 1_793_929_260_000L

        val NO_ACTIONS = HomeActions({}, {}, {}, {}, {}, {}, {})

        /** #208: the 「节点」 row as the home view model fills it from the mock (main group 节点选择 → 新加坡 02). */
        fun picker(e: com.zephyr.engine.ZephyrEngine, scenes: List<com.zephyr.engine.Scene>): com.zephyr.app.ui.home.NodePickerUi = runBlocking {
            val groups = e.policyGroups().first()
            val main = com.zephyr.app.ui.home.MainGroup.main(groups, e.finalPolicy())
            val label = main?.let { com.zephyr.app.ui.home.MainGroup.label(com.zephyr.app.ui.home.MainGroup.chain(it, groups)) }
            com.zephyr.app.ui.home.NodePickerUi(
                label = label,
                latencyMs = scenes.firstOrNull { it.selected.name == label }?.selected?.latencyMs,
                groups = com.zephyr.app.ui.home.MainGroup.selectGroups(groups, null).map { it.name },
                group = main?.name, selectedName = main?.selected,
            )
        }
        val NO_CB = HomeCallbacks({}, { _, _ -> }, {}, {}, {})

        @JvmStatic
        @Parameterized.Parameters(name = "dark={0},accent={1},font={2}")
        fun params(): List<Array<Any>> = buildList {
            for (dark in listOf(true, false)) for (a in ZAccent.entries) add(arrayOf(dark, a, 1f))
            add(arrayOf(true, ZAccent.BLUE, 1.6f))
            add(arrayOf(false, ZAccent.BLUE, 1.6f))
        }
    }
}
