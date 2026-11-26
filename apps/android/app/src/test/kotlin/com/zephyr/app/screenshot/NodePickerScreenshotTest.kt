package com.zephyr.app.screenshot

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import com.zephyr.app.ui.home.HomeContent
import com.zephyr.app.ui.home.HomeLive
import com.zephyr.app.ui.home.HomeUi
import com.zephyr.design.theme.ZephyrTheme
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** #208: Home's node sheet open on the main group (chips, search, sort, current check), light and dark. */
@RunWith(Parameterized::class)
class NodePickerScreenshotTest(private val dark: Boolean) {
    @get:Rule
    val zone = FixedZoneRule()

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_9.copy(nightMode = if (dark) NightMode.NIGHT else NightMode.NOTNIGHT, locale = "zh"),
        maxPercentDifference = 0.1,
    )

    @Test
    fun sheet() {
        val e = MockEngine(clock = { HomeScreenshotTest.NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        val conn = runBlocking { e.connectionState().first() }
        val scenes = runBlocking { e.scenes().first() }
        val subs = runBlocking { e.subscriptions().first() }
        val spark = runBlocking { e.recentTraffic(90) }
        val base = HomeScreenshotTest.picker(e, scenes)
        val rows = runBlocking { e.groupMembers(base.group!!, 0, 40).rows }
        val picker = base.copy(open = true, raw = rows, rows = rows, selectedName = rows[1].name)
        val ui = HomeUi(now = HomeScreenshotTest.NOW, usage = runBlocking { e.usageToday() })
        val live = HomeLive(traffic = spark.last(), spark = spark.map { it.downBps.toFloat() }, now = HomeScreenshotTest.NOW)
        paparazzi.snapshot {
            ZephyrTheme(dark = dark, accent = ZAccent.BLUE) {
                HomeContent(conn, scenes, subs, ui, { live }, HomeScreenshotTest.NO_ACTIONS, HomeScreenshotTest.NO_CB, picker = picker)
            }
        }
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "dark={0}")
        fun params(): List<Array<Any>> = listOf(arrayOf(false), arrayOf(true))
    }
}
