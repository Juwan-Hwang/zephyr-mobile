package com.zephyr.app.screenshot

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.NightMode
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.first
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.activity.ActivitySheet
import com.zephyr.app.ui.activity.TraceSheet
import com.zephyr.app.ui.nodes.NodesScreen
import com.zephyr.app.ui.nodes.NodesViewModel
import com.zephyr.app.ui.rules.RulesScreen
import com.zephyr.app.ui.scene.SceneSheet
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
    val zone = FixedZoneRule()

    @get:Rule
    val paparazzi = Paparazzi(
        // Baselines are the Chinese UI; English is the resource default, so pin the locale.
        deviceConfig = DeviceConfig.PIXEL_9.copy(nightMode = if (dark) NightMode.NIGHT else NightMode.NOTNIGHT, locale = "zh"),
        maxPercentDifference = 0.1,
    )

    private lateinit var engine: MockEngine

    @Before fun setUp() {
        engine = MockEngine(clock = { HomeScreenshotTest.NOW }, demo = true, compute = kotlinx.coroutines.Dispatchers.Unconfined, measure = { 120L })
        AppGraph.override(engine)
    }

    @Test fun nodes() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { NodesScreen(NodesViewModel(engine), "", onBack = {}) } } }
    @Test fun nodesSearch() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { NodesScreen(NodesViewModel(engine), "日本 NTT", onBack = {}) } } }
    @Test fun rules() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalInspectionMode provides true) { RulesScreen("chat.openai.com", onBack = {}) } } } }
    @Test fun subscriptions() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { SubscriptionsScreen(onBack = {}, onImport = {}) } } }
    @Test fun settings() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) { SettingsScreen(com.zephyr.app.ui.common.BackTo.LIBRARY, onBack = {}) } } }

    @Test fun activity() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) {
        androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) { ActivitySheet(true, {}, null, onHost = {}) } } } }
    @Test fun trace() = paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) {
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalInspectionMode provides true) { androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) { TraceSheet("claude.ai") {} } } } } }

    /** J-6 (spec §9.6): the scene sheet with its latency tick bar over the mock candidate pool. */
    @Test fun sceneSheet() {
        val scene = kotlinx.coroutines.runBlocking { engine.scenes().first().first() }
        paparazzi.snapshot { ZephyrTheme(dark = dark) { androidx.compose.runtime.CompositionLocalProvider(com.zephyr.app.ui.common.LocalNow provides { HomeScreenshotTest.NOW }) {
            androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxSize()) { SceneSheet(scene, onDismiss = {}) } } } }
    }

    /** J-6 tick bar alone, fixed data: slow ticks amber, the selected exit (id 2) tall accent, > 600 ms at the right end, 「超时 2」. */
    @Test fun latencyTickBar() = paparazzi.snapshot { ZephyrTheme(dark = dark) {
        val ms = listOf(38, 64, 92, 120, 150, 188, 210, 260, 407, 720, -1, -1, null)
        val nodes = ms.mapIndexed { i, m -> com.zephyr.engine.NodeSummary(id = i.toLong(), name = "n$i", region = "JP", protocol = "", latencyMs = m) }
        androidx.compose.foundation.layout.Box(androidx.compose.ui.Modifier.fillMaxWidth().background(com.zephyr.design.theme.ZTheme.colors.bg).padding(horizontal = 36.dp, vertical = 24.dp)) {
            com.zephyr.app.ui.scene.LatencyTickBar(nodes, selectedId = 2L)
        }
    } }

    /** J-3 (spec §9.5): grouped command results, action labels, bold Enter row = keyboard highlight on the 2nd row, group footers. */
    @Test fun commandResults() = paparazzi.snapshot { ZephyrTheme(dark = dark) {
        val r = com.zephyr.app.ui.command.CommandResults.rows(listOf(
            Triple("全局", "所有流量经由一个节点", com.zephyr.app.ui.command.CommandTarget.Mode(com.zephyr.engine.ProxyMode.GLOBAL)),
            Triple("AI", "东京 03", com.zephyr.app.ui.command.CommandTarget.Scene("ai")),
            Triple("日本 东京 01 NTT", "JP · 38 ms", com.zephyr.app.ui.command.CommandTarget.Nodes("日本", 1)),
            Triple("日本 大阪 02", "JP · 64 ms", com.zephyr.app.ui.command.CommandTarget.Nodes("日本", 2)),
            Triple("本地代理端口", null, com.zephyr.app.ui.command.CommandTarget.Page(com.zephyr.app.ui.command.CommandPage.LOCAL_PROXY)),
            Triple("claude.ai 走哪里？", null, com.zephyr.app.ui.command.CommandTarget.Rule("claude.ai")),
        ))
        val groups = com.zephyr.app.ui.command.CommandResults.groups(r)
        androidx.compose.foundation.layout.Column(androidx.compose.ui.Modifier.fillMaxSize().background(com.zephyr.design.theme.ZTheme.colors.bg).padding(horizontal = 12.dp)) {
            com.zephyr.app.ui.command.CommandResultList(groups, emptySet(), highlighted = r[1].key, defaultKey = r[1].key, onRun = {}, onExpand = {},
                nodeFooter = "在节点库中查看全部 1,204 个")
        }
    } }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "dark={0}")
        fun params() = listOf(arrayOf<Any>(true), arrayOf<Any>(false))
    }
}
