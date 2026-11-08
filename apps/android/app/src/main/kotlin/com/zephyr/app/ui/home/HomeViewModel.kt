package com.zephyr.app.ui.home

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zephyr.app.di.AppGraph
import com.zephyr.engine.ConnectionState
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.ExitChange
import com.zephyr.engine.NodeId
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.Scene
import com.zephyr.engine.Subscription
import com.zephyr.engine.TrafficSample
import com.zephyr.engine.UsageSummary
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.flatMapLatest

@Immutable
data class PendingChange(
    val scene: Scene, val node: NodeSummary, val change: ExitChange,
    /** Set when the change came from choosing "Zephyr 优选" on an AI scene: record the source after confirm. */
    val thenSource: com.zephyr.engine.SceneSource? = null,
)

@Immutable
data class UndoToast(
    val message: String, val sceneId: String?, val previousNodeId: NodeId?, val serial: Long,
    /** Overrides the scene-swap undo (pins, host overrides). */
    val undoAction: (suspend () -> Unit)? = null,
)

/** Fast-changing values (1 Hz clock, traffic samples), read only by the status and traffic rows (review H-P1-5). */
@Immutable
data class HomeLive(
    val traffic: TrafficSample = TrafficSample(0, 0, 0),
    val spark: List<Float> = emptyList(),
    val now: Long = System.currentTimeMillis(),
)

@Immutable
data class HomeUi(
    /** Minute-granular clock for "x 分钟前检测" / expiry text; the 1 Hz clock lives in [HomeLive]. */
    val now: Long = System.currentTimeMillis(),
    val usage: UsageSummary? = null,
    val pending: PendingChange? = null,
    val toast: UndoToast? = null,
    /** Scrub slots per scene (prototype `#aiTrack`): best node of each region in the scene's pool, current included. */
    val slots: Map<String, List<NodeSummary>> = emptyMap(),
    /** Global mode: the exit now, and the inline "更换节点" proposal when open (prototype `gcf`). */
    val globalNode: NodeSummary? = null,
    val globalProposal: NodeSummary? = null,
    val globalChange: com.zephyr.engine.ExitChange? = null,
)

class HomeViewModel(private val engine: ZephyrEngine = AppGraph.engine) : ViewModel() {
    val connection: StateFlow<ConnectionState> = engine.connectionState().stateIn(viewModelScope, SharingStarted.Eagerly, ConnectionState())
    val scenes: StateFlow<List<Scene>> = engine.scenes().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val subscriptions: StateFlow<List<Subscription>> = engine.subscriptions().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _ui = MutableStateFlow(HomeUi())
    val ui: StateFlow<HomeUi> = _ui.asStateFlow()
    /** App-level toast (drawn above sheets in AppRoot) without the 1 Hz home churn. */
    val toast: StateFlow<UndoToast?> = _ui.map { it.toast }.distinctUntilChanged().stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /** Engine errors become a visible toast instead of a crash or a silent no-op (review H-P1-2). */
    private fun launchCatching(what: String, block: suspend () -> Unit) = viewModelScope.launch {
        try { block() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
            android.util.Log.w("Zephyr", "$what failed", e)
            showToast(errorText(what, (e as? com.zephyr.engine.ZephyrException)?.error?.code), null, null)
        }
    }
    private var toastJob: Job? = null
    private var toastSerial = 0L

    init {
        viewModelScope.launch { _ui.update { it.copy(usage = engine.usageToday()) } }
        // Core switched a dead scene exit to a hot standby: say so, offer the undo (contract §14 场景自动切换).
        (engine as? com.zephyr.engine.core.CoreEngine)?.let { core ->
            viewModelScope.launch { core.failovers.collect { f ->
                if (f.now == null) showToast("${f.sceneName} 出口无响应，出口 IP 不会自动更换", null, null)
                else showToast("${f.sceneName} 出口已自动切换到 ${f.now}", f.sceneId, f.previous)
            } }
        }
        viewModelScope.launch {
            connection.map { it.mode }.distinctUntilChanged().collectLatest { m ->
                if (m == ProxyMode.GLOBAL) runCatching { globalNow() }.getOrNull()?.let { n -> _ui.update { it.copy(globalNode = n) } }
                else _ui.update { it.copy(globalProposal = null) }
            }
        }
        // Minute clock for the slow rows; the 1 Hz one is [live], and only while the screen collects it.
        viewModelScope.launch {
            while (true) {
                delay(60_000 - System.currentTimeMillis() % 60_000)
                val u = runCatching { engine.usageToday() }.getOrNull()
                _ui.update { it.copy(now = System.currentTimeMillis(), usage = u ?: it.usage) }
            }
        }
    }

    private val clock = kotlinx.coroutines.flow.flow { while (true) { emit(System.currentTimeMillis()); delay(1_000 - System.currentTimeMillis() % 1_000) } }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private val trafficLive = connection.map { it.status == ConnectionStatus.CONNECTED }.distinctUntilChanged().flatMapLatest<Boolean, Pair<TrafficSample, List<Float>>> { on ->
        if (!on) kotlinx.coroutines.flow.flowOf(TrafficSample(0, 0, 0) to emptyList<Float>())
        else kotlinx.coroutines.flow.flow {
            // Ring of the last 90 samples; one snapshot list per sample instead of two concatenations.
            val ring = FloatArray(SPARK_POINTS); var n = 0; var head = 0
            fun push(v: Float) { ring[head] = v; head = (head + 1) % SPARK_POINTS; if (n < SPARK_POINTS) n++ }
            fun snapshot() = List(n) { i -> ring[(head - n + i + SPARK_POINTS) % SPARK_POINTS] }
            val back = engine.recentTraffic(SPARK_POINTS)
            back.forEach { push(it.downBps.toFloat()) }
            emit((back.lastOrNull() ?: TrafficSample(0, 0, 0)) to snapshot())
            engine.traffic().collect { s -> push(s.downBps.toFloat()); emit(s to snapshot()) }
        }
    }

    /** Stops 5 s after the home screen stops collecting (background, other screen): no FFI polling then. */
    val live: StateFlow<HomeLive> = kotlinx.coroutines.flow.combine(clock, trafficLive) { now, (t, sp) -> HomeLive(t, sp, now) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeLive())

    fun setMode(mode: ProxyMode) = launchCatching("切换模式") { engine.setMode(mode) }

    /**
     * Loads the scrub slots for a row: one per region the scene's pool covers, its fastest node, ordered by
     * [REGION_ORDER] then code; the current exit occupies its region's slot. No looping, no hard-coded list (H-P1-3).
     */
    fun prefetchSlots(scene: Scene) = viewModelScope.launch {
        val pool = runCatching { engine.sceneCandidates(scene.id, null) }.getOrDefault(emptyList())
        val byRegion = (pool + scene.selected).filter { it.id >= 0 && it.region.isNotBlank() }.groupBy { it.region.uppercase() }
        val slots = byRegion.map { (r, ns) -> ns.firstOrNull { it.id == scene.selected.id } ?: ns.minBy { it.latencyMs ?: Int.MAX_VALUE } }
            .sortedWith(compareBy({ REGION_ORDER.indexOf(it.region.uppercase()).let { i -> if (i < 0) Int.MAX_VALUE else i } }, { it.region.uppercase() }))
        _ui.update { it.copy(slots = it.slots + (scene.id to slots)) }
    }

    /** A candidate tapped in the scene sheet: same inline confirm as the swipe (exit IP line, 更改/取消). */
    fun pick(scene: Scene, node: NodeSummary) = launchCatching("预览出口") {
        if (node.id == scene.selected.id) return@launchCatching
        val change = engine.previewSceneChange(scene.id, node.id)
        _ui.update { it.copy(pending = PendingChange(scene, node, change)) }
    }

    /**
     * 订阅分组 / Zephyr 优选. Choosing 优选 may move the exit to the best node; for AI that is an exit-IP change,
     * so it goes through the inline confirm first and the source is recorded only after "更改" (§14.y).
     */
    fun setSource(scene: Scene, source: com.zephyr.engine.SceneSource) = launchCatching("切换来源") {
        if (scene.kind == com.zephyr.engine.SceneKind.AI && source == com.zephyr.engine.SceneSource.AUTO) {
            val best = engine.sceneCandidates(scene.id, null).firstOrNull()
            if (best != null && best.id != scene.selected.id) {
                val change = engine.previewSceneChange(scene.id, best.id)
                _ui.update { it.copy(pending = PendingChange(scene, best, change, thenSource = source)) }
                return@launchCatching
            }
        }
        val previous = scene.selected.id
        val now = engine.setSceneSource(scene.id, source)
        if (now != null && now.id != previous) showToast("已切换至${now.name}", scene.id, previous)
    }

    fun confirmPending() = launchCatching("切换出口") {
        val p = _ui.value.pending ?: return@launchCatching
        val previous = p.scene.selected.id
        engine.applySceneChange(p.scene.id, p.node.id)
        p.thenSource?.let { runCatching { engine.setSceneSource(p.scene.id, it) } }
        _ui.update { it.copy(pending = null) }
        showToast("已切换至${p.node.name}", p.scene.id, previous)
    }

    /** Prototype `#gChange`: toggles an inline proposal (fastest other node), confirmed with "更改为X". */
    fun toggleGlobalChange() = launchCatching("读取节点") {
        if (_ui.value.globalProposal != null) { _ui.update { it.copy(globalProposal = null) }; return@launchCatching }
        val cur = globalNow()
        val page = engine.groupMembers(com.zephyr.engine.core.CoreEngine.GLOBAL, 0, 500).rows
        val best = page.filter { it.protocol.uppercase() !in NON_NODES && it.name != cur?.name && it.id >= 0 }
            .minByOrNull { it.latencyMs ?: Int.MAX_VALUE } ?: throw com.zephyr.engine.ZephyrException(com.zephyr.engine.ErrorCode.NODE_NOT_FOUND, "no other node")
        val x = runCatching { engine.previewGlobalChange(best.id) }.getOrNull()
        _ui.update { it.copy(globalNode = cur, globalProposal = best, globalChange = x) }
    }

    fun confirmGlobal() = launchCatching("切换节点") {
        val to = _ui.value.globalProposal ?: return@launchCatching
        val from = _ui.value.globalNode
        engine.setGlobalNode(to.id)
        _ui.update { it.copy(globalProposal = null, globalNode = to) }
        showToast("已切换至${to.name}", null, null, from?.let { f -> { engine.setGlobalNode(f.id); _ui.update { u -> u.copy(globalNode = f) } } })
    }

    private suspend fun globalNow(): NodeSummary? {
        (engine as? com.zephyr.engine.core.CoreEngine)?.globalNode()?.let { return it }
        val name = engine.policyGroups().first().firstOrNull { it.name == com.zephyr.engine.core.CoreEngine.GLOBAL }?.selected
        val rows = engine.groupMembers(com.zephyr.engine.core.CoreEngine.GLOBAL, 0, 500).rows
        return rows.firstOrNull { it.name == name } ?: connection.value.globalNodeId?.let { id -> rows.firstOrNull { it.id == id } }
    }

    fun cancelPending() = _ui.update { it.copy(pending = null) }

    fun undo() = launchCatching("撤销") {
        val t = _ui.value.toast ?: return@launchCatching
        val u = t.undoAction
        if (u != null) runCatching { u() }
        else if (t.sceneId != null && t.previousNodeId != null) engine.applySceneChange(t.sceneId, t.previousNodeId)
        _ui.update { it.copy(toast = null) }
    }

    /** Applies a command the user saw previewed (exit-IP line included) and confirmed with "应用". */
    fun applyCommand(plan: com.zephyr.app.ui.command.CommandPlan) = viewModelScope.launch {
        when (plan) {
            is com.zephyr.app.ui.command.CommandPlan.Exit -> runCatching {
                val appId = plan.appId
                if (appId != null) {
                    // "Gemini 走日本" pins Gemini only (prototype 1054: AI 行显示「Gemini：东京 03」); GPT/Claude untouched.
                    engine.setSceneException(plan.scene.id, appId, plan.node.id)
                    val prevPin = plan.previousPin
                    showToast("${plan.who} 现使用${plan.node.name}", null, null) { engine.setSceneException(plan.scene.id, appId, prevPin) }
                } else {
                    val prev = plan.scene.selected.id.takeIf { it >= 0 }
                    engine.applySceneChange(plan.scene.id, plan.node.id)
                    showToast("${plan.who} 现使用${plan.node.name}", plan.scene.id, prev)
                }
            }.onFailure { showToast("未能应用：${plan.who}", null, null) }
            is com.zephyr.app.ui.command.CommandPlan.Direct -> runCatching {
                engine.overrideHost(plan.host, com.zephyr.engine.TraceTarget.DIRECT, null, persistent = true)
                showToast("${plan.who} 现为直连", null, null) {
                    engine.overrideHost(plan.host, com.zephyr.engine.TraceTarget.UNCHANGED, null, persistent = true)
                }
            }.onFailure { showToast("未能应用：${plan.who}", null, null) }
            is com.zephyr.app.ui.command.CommandPlan.NoNodes -> Unit
        }
    }

    private fun showToast(msg: String, sceneId: String?, prev: NodeId?, undo: (suspend () -> Unit)? = null) {
        toastJob?.cancel()
        val serial = ++toastSerial
        _ui.update { it.copy(toast = UndoToast(msg, sceneId, prev, serial, undo)) }
        toastJob = viewModelScope.launch {
            delay(com.zephyr.design.tokens.ZMotion.undoWindow.toLong())
            _ui.update { if (it.toast?.serial == serial) it.copy(toast = null) else it }
        }
    }

    companion object {
        /** Group/built-in members of GLOBAL that are not exits. */
        private val NON_NODES = setOf("SELECTOR", "URLTEST", "FALLBACK", "LOADBALANCE", "RELAY", "DIRECT", "REJECT", "REJECTDROP", "PASS", "COMPATIBLE")
        const val SPARK_POINTS = 90
        val REGION_ORDER = listOf("HK", "TW", "JP", "KR", "SG", "US", "GB", "DE", "FR", "NL", "CA", "AU")
        fun preview() = HomeViewModel(MockEngine(demo = true))
    }
}

/** One line, what happened and what to do; never a raw exception. */
internal fun errorText(what: String, code: com.zephyr.engine.ErrorCode?): String = when (code) {
    com.zephyr.engine.ErrorCode.NOT_RUNNING -> "$what 需要先连接"
    com.zephyr.engine.ErrorCode.SUBSCRIPTION_NOT_FOUND -> "先添加一个订阅"
    com.zephyr.engine.ErrorCode.NETWORK_UNAVAILABLE -> "网络不可用"
    com.zephyr.engine.ErrorCode.NODE_NOT_FOUND, com.zephyr.engine.ErrorCode.SCENE_NOT_FOUND -> "$what 失败：节点已不存在"
    else -> "$what 失败"
}
