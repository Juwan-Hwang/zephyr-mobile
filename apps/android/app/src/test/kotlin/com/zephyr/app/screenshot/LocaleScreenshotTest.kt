package com.zephyr.app.screenshot

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.home.HomeContent
import com.zephyr.app.ui.home.HomeLive
import com.zephyr.app.ui.home.HomeUi
import com.zephyr.app.ui.subs.SubscriptionsScreen
import com.zephyr.design.theme.ZephyrTheme
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * Translation acceptance (D-P2-12 phase 2a): Home in the connected demo state plus Subscriptions (the text-heaviest page) per
 * left-to-right locale, dark, BLUE, font 1×. Same MockEngine data as [HomeScreenshotTest] / [PagesScreenshotTest].
 */
@RunWith(Parameterized::class)
class LocaleScreenshotTest(private val locale: String) {

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_9.copy(nightMode = NightMode.NIGHT, fontScale = 1f, locale = locale),
        maxPercentDifference = 0.1,
    )

    private lateinit var engine: MockEngine

    @Before fun setUp() {
        engine = MockEngine(clock = { HomeScreenshotTest.NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        AppGraph.override(engine)
    }

    @Test
    fun home() {
        val (conn, scenes, subs) = runBlocking { Triple(engine.connectionState().first(), engine.scenes().first(), engine.subscriptions().first()) }
        val usage = runBlocking { engine.usageToday() }
        val spark = runBlocking { engine.recentTraffic(90) }
        val ui = HomeUi(now = HomeScreenshotTest.NOW, usage = usage)
        val live = HomeLive(traffic = spark.last(), spark = spark.map { it.downBps.toFloat() }, now = HomeScreenshotTest.NOW)
        paparazzi.snapshot {
            ZephyrTheme(dark = true, accent = ZAccent.BLUE) {
                HomeContent(conn, scenes, subs, ui, { live }, HomeScreenshotTest.NO_ACTIONS, HomeScreenshotTest.NO_CB)
            }
        }
    }

    @Test
    fun subscriptions() = paparazzi.snapshot {
        ZephyrTheme(dark = true, accent = ZAccent.BLUE) {
            androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) {
                SubscriptionsScreen(onBack = {}, onImport = {})
            }
        }
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun params(): List<Array<Any>> = listOf("ja", "ko", "ru", "es", "tr", "vi", "sw", "tk", "my").map { arrayOf<Any>(it) }
    }
}
