package com.zephyr.app.ui.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.zephyr.design.components.ZIconButton
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZSparkline
import com.zephyr.design.components.ZSurface
import com.zephyr.design.components.ZSurfaceStyle
import com.zephyr.design.components.ZText
import com.zephyr.design.components.ZToast
import com.zephyr.design.components.ZTrafficStat
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene

data class HomeActions(
    val onToggle: (Boolean) -> Unit,
    val onSettings: () -> Unit,
    val onLibrary: () -> Unit,
    val onCommand: () -> Unit,
    val onToday: () -> Unit,
    val onSubscriptions: () -> Unit,
    val onScene: (Scene) -> Unit,
    val onChangeGlobalNode: () -> Unit,
    val onActivity: () -> Unit = {},
)

@Composable
fun HomeScreen(vm: HomeViewModel, actions: HomeActions) {
    val conn by vm.connection.collectAsStateWithLifecycle()
    val scenes by vm.scenes.collectAsStateWithLifecycle()
    val subs by vm.subscriptions.collectAsStateWithLifecycle()
    val ui by vm.ui.collectAsStateWithLifecycle()
    val live = vm.live.collectAsStateWithLifecycle()
    HomeContent(
        conn, scenes, subs, ui, { live.value }, actions,
        HomeCallbacks({ vm.setMode(it) }, { s, n -> vm.pick(s, n) }, { vm.confirmPending() }, { vm.cancelPending() }, { vm.undo() }, { vm.toggleGlobalChange() }, { vm.confirmGlobal() }, { vm.prefetchSlots(it) }),
    )
}

/** VM-side callbacks, split out so screenshot tests can render [HomeContent] from plain data. */
data class HomeCallbacks(
    val setMode: (ProxyMode) -> Unit,
    val pick: (Scene, com.zephyr.engine.NodeSummary) -> Unit,
    val confirm: () -> Unit,
    val cancel: () -> Unit,
    val undo: () -> Unit,
    val toggleGlobalChange: () -> Unit = {},
    val confirmGlobal: () -> Unit = {},
    val prefetchSlots: (Scene) -> Unit = {},
)

@Composable
fun HomeContent(
    conn: com.zephyr.engine.ConnectionState,
    scenes: List<Scene>,
    subs: List<com.zephyr.engine.Subscription>,
    ui: HomeUi,
    /** Read inside the status/traffic rows only, so 1 Hz updates recompose those two rows and nothing else. */
    live: () -> HomeLive,
    actions: HomeActions,
    cb: HomeCallbacks,
) {
    val c = ZTheme.colors
    val connected = conn.status == ConnectionStatus.CONNECTED
    val list = rememberLazyListState()

    Box(Modifier.fillMaxSize().background(c.bg)) {
        LazyColumn(state = list, // Review A-P2-5: clear the command bar plus the 3-button nav bar.
            contentPadding = PaddingValues(bottom = 120.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()), modifier = Modifier.fillMaxSize()) {
            item("inset") { Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars).padding(top = 8.dp)) }
            item("top") { Spacer(Modifier.height(12.dp)); HomeTopBar(conn.status, actions.onSettings) }
            item("status") {
                Spacer(Modifier.height(24.dp))
                HomeStatus(conn, live().now, scenes.size, actions.onToggle, cb.setMode)
            }
            item("traffic") {
                AnimatedVisibility(connected, enter = expandVertically(ZAnim.slow()) + fadeIn(ZAnim.slow()), exit = shrinkVertically(ZAnim.standard()) + fadeOut(ZAnim.micro())) {
                    Column {
                        val l = live()
                        Spacer(Modifier.height(36.dp))
                        ZTrafficStat(l.traffic.downBps, l.traffic.upBps, Modifier.padding(horizontal = 22.dp).zPressable(label = "最近连接", onClick = actions.onActivity))
                        ZSparkline(l.spark, Modifier.fillMaxWidth().height(72.dp), description = "最近 90 秒下载速率")
                    }
                }
                if (!connected) Spacer(Modifier.height(150.dp))
            }
            item("scenes-h") {
                Spacer(Modifier.height(28.dp))
                val tested = scenes.mapNotNull { it.testedAt }.maxOrNull()
                ZSectionHeader("场景", trailing = if (conn.mode == ProxyMode.GLOBAL) null else tested?.let { ZFormat.ago(it, ui.now).let { a -> if (a == "刚刚") "刚刚检测" else a.replace("前", "前检测") } })
            }
            item("scenes") {
                if (conn.mode == ProxyMode.GLOBAL) {
                    GlobalModeCard(ui.globalNode, ui.globalProposal, ui.globalChange, onUseRule = { cb.setMode(ProxyMode.RULE) }, onChangeNode = cb.toggleGlobalChange, onConfirm = cb.confirmGlobal)
                } else {
                    SceneCard(scenes, ui.pending, ui.slots, cb.pick, cb.prefetchSlots, { cb.confirm() }, cb.cancel, actions.onScene)
                }
            }
            item("subs-h") {
                Spacer(Modifier.height(28.dp))
                ZSectionHeader("订阅", trailing = ui.usage?.let { "今日 ${ZFormat.bytesText(it.todayBytes)}" }, onTrailing = actions.onToday)
            }
            item("subs") { SubscriptionsCard(subs, ui.now, actions.onSubscriptions) }
        }

        // Fade content under the bottom bar, then the floating command bar (prototype `.dock`).
        Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(140.dp)
                .background(Brush.verticalGradient(listOf(c.bg.copy(alpha = 0f), c.bg.copy(alpha = 0.92f), c.bg))),
        )
        Row(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            ZSurface(Modifier.weight(1f).height(52.dp).zPressable(label = "搜索或输入指令", onClick = actions.onCommand), style = ZSurfaceStyle.Glass, shape = ZTheme.shapes.pill) {
                Row(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    ZIcon(ZIcons.Search, tint = c.text2, size = 20.dp)
                    Spacer(Modifier.width(12.dp))
                    ZText("搜索或输入指令", style = ZTheme.type.body, color = c.text3)
                }
            }
            Spacer(Modifier.width(10.dp))
            ZIconButton(ZIcons.Grid, "资料库", actions.onLibrary, filled = true, size = 52.dp)
        }
    }
}
