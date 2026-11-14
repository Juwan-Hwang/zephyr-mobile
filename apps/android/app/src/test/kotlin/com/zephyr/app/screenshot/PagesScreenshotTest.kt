package com.zephyr.app.screenshot

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import androidx.compose.foundation.layout.fillMaxSize
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.activity.ActivitySheet
import com.zephyr.app.ui.activity.TraceSheet
import com.zephyr.app.ui.nodes.NodesScreen
import com.zephyr.app.ui.nodes.NodesViewModel
import com.zephyr.app.ui.rules.RulesScreen
import com.zephyr.app.ui.settings.SettingsScreen
import com.zephyr.app.ui.subs.SubscriptionsScreen
import com.zephyr.design.theme.ZephyrTheme
import com.zephyr.engine.mock.MockEngine
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Library pages, dark + light, fed by the deterministic MockEngine (same data as the prototype). */
@RunWith(Parameterized::class)
class PagesScreenshotTest(private val dark: Boolean) {
    @get:Rule
    val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig.PIXEL_9.copy(nightMode = if (dark) NightMode.NIGHT else NightMode.NOTNIGHT),
        maxPercentDifference = 0.1,
    )

    private lateinit var engine: MockEngine

    @Before fun setUp() {
        engine = MockEngine(clock = { HomeScreenshotTest.NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        AppGraph.override(engine)
    }

    @Test fun nodes() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { NodesScreen(NodesViewModel(engine), "", onBack = {}) } } }
    @Test fun nodesSearch() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { NodesScreen(NodesViewModel(engine), "日本 NTT", onBack = {}) } } }
    @Test fun rules() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { RulesScreen("chat.openai.com", onBack = {}) } } }
    @Test fun subscriptions() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { SubscriptionsScreen(onBack = {}, onImport = {}) } } }
    @Test fun settings() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { SettingsScreen("资料库", onBack = {}) } } }

    @Test fun activity() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) {
        androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) { ActivitySheet(true, {}, null, onHost = {}) } } } }
    @Test fun trace() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) {
        androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) { TraceSheet("claude.ai") {} } } } }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "dark={0}")
        fun params() = listOf(arrayOf<Any>(true), arrayOf<Any>(false))
    }
}
