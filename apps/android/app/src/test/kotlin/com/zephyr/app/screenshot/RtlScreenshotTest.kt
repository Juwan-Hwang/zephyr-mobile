package com.zephyr.app.screenshot

import androidx.compose.runtime.CompositionLocalProvider
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.LayoutDirection
import com.android.resources.NightMode
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.LocalNow
import com.zephyr.app.ui.home.HomeContent
import com.zephyr.app.ui.home.HomeLive
import com.zephyr.app.ui.home.HomeUi
import com.zephyr.app.ui.settings.SettingsScreen
import com.zephyr.app.ui.subs.SubscriptionsScreen
import com.zephyr.design.theme.ZephyrTheme
import com.zephyr.design.tokens.ZAccent
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * Right-to-left acceptance (D-P2-12 phase 2b): Home plus two library pages (back chevron, chevron rows, toggles,
 * progress bars) in Arabic, Persian and Urdu, dark, blue accent, 1× font, with the layout mirrored the way the
 * device does it (manifest supportsRtl + an RTL locale), not forced inside the composition.
 */
@RunWith(Parameterized::class)
class RtlScreenshotTest(private val lang: String) {

    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_9.copy(
            nightMode = NightMode.NIGHT,
            fontScale = 1f,
            locale = lang,
            layoutDirection = LayoutDirection.RTL,
        ),
        supportsRtl = true,
        maxPercentDifference = 0.1,
    )

    private fun engine() = MockEngine(clock = { HomeScreenshotTest.NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })

    @Test
    fun home() {
        val e = engine()
        val conn = runBlocking { e.connectionState().first() }
        val scenes = runBlocking { e.scenes().first() }
        val subs = runBlocking { e.subscriptions().first() }
        val usage = runBlocking { e.usageToday() }
        val spark = runBlocking { e.recentTraffic(90) }
        val ui = HomeUi(now = HomeScreenshotTest.NOW, usage = usage)
        val live = HomeLive(traffic = spark.last(), spark = spark.map { it.downBps.toFloat() }, now = HomeScreenshotTest.NOW)
        paparazzi.snapshot {
            ZephyrTheme(dark = true, accent = ZAccent.BLUE) {
                HomeContent(conn, scenes, subs, ui, { live }, HomeScreenshotTest.NO_ACTIONS, HomeScreenshotTest.NO_CB)
            }
        }
    }

    @Test
    fun settings() {
        AppGraph.override(engine())
        paparazzi.snapshot {
            ZephyrTheme(dark = true, accent = ZAccent.BLUE) {
                CompositionLocalProvider(LocalNow provides { HomeScreenshotTest.NOW }) { SettingsScreen(BackTo.LIBRARY, onBack = {}) }
            }
        }
    }

    @Test
    fun subscriptions() {
        AppGraph.override(engine())
        paparazzi.snapshot {
            ZephyrTheme(dark = true, accent = ZAccent.BLUE) {
                CompositionLocalProvider(LocalNow provides { HomeScreenshotTest.NOW }) { SubscriptionsScreen(onBack = {}, onImport = {}) }
            }
        }
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "lang={0}")
        fun params(): List<Array<Any>> = listOf("ar", "fa", "ur").map { arrayOf<Any>(it) }
    }
}
