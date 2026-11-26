package com.zephyr.app.ui.home

import com.zephyr.app.ui.common.sceneNameText
import androidx.annotation.StringRes
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiText
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
import kotlinx.coroutines.flow.filterNotNull
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
    val message: UiText, val sceneId: String?, val previousNodeId: NodeId?, val serial: Long,
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
    /** Mini funnel per scene row (spec §9.3, contract v0.7 §19.a `sceneFunnel`); missing = not counted, row keeps its text. */
    val funnels: Map<String, com.zephyr.engine.NodeFunnel> = emptyMap(),
    /** Global mode: the exit now, and the inline "更换节点" proposal when open (prototype `gcf`). */
    val globalNode: NodeSummary? = null,
    val globalProposal: NodeSummary? = null,
    val globalChange: com.zephyr.engine.ExitChange? = null,
    /** "更换节点" is open: the proposal (when there is one) and 「浏览全部节点」 (iOS GlobalModeCard). */
    val globalOpen: Boolean = false,
)

class HomeViewModel(private val engine: ZephyrEngine = AppGraph.engine) : ViewModel() {
    val connection: StateFlow<ConnectionState> = engine.connectionState().stateIn(viewModelScope, SharingStarted.Eagerly, ConnectionState())
    val scenes: StateFlow<List<Scene>> = engine.scenes().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val subscriptions: StateFlow<List<Subscription>> = engine.subscriptions().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /**
     * Issue #1 (S25 Ultra): nodes in the imported profiles, read from the store (core `subscriptionsSummary`) whenever
     * the scenes or the subscription list move — not from the running core, so it is there before the first connect
     * and after a failed one. Rows with no exit yet show it instead of "0 个可用".
     */
    val profileNodes: StateFlow<Long> = kotlinx.coroutines.flow.merge(engine.scenes().map { }, engine.subscriptions().map { })
        .map { runCatching { engine.subscriptionsSummary().totalNodes }.getOrDefault(0L) }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0L)

    private val _ui = MutableStateFlow(HomeUi())
    val ui: StateFlow<HomeUi> = _ui.asStateFlow()
    /** App-level toast (drawn above sheets in AppRoot) without the 1 Hz home churn. */
    val toast: StateFlow<UndoToast?> = _ui.map { it.toast }.distinctUntilChanged().stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /** Engine errors become a visible toast instead of a crash or a silent no-op (review H-P1-2). */
    private fun launchCatching(@StringRes what: Int, block: suspend () -> Unit) = viewModelScope.launch {
        try { block() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
            android.util.Log.w("Zephyr", "action failed", e)
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
                val to = f.now
                if (to == null) showToast(uiText(R.string.home_failover_none, sceneNameText(f.sceneName)), null, null)
                else showToast(uiText(R.string.home_failover_switched, sceneNameText(f.sceneName), to), f.sceneId, f.previous)
            } }
        }
        viewModelScope.launch {
            connection.map { it.mode }.distinctUntilChanged().collectLatest { m ->
                if (m == ProxyMode.GLOBAL) runCatching { globalNow() }.getOrNull()?.let { n -> _ui.update { it.copy(globalNode = n) } }
                else _ui.update { it.copy(globalProposal = null, globalOpen = false) }
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

    /** Contract §22.b: Home's 错误详情 goes through the engine (core `redactDiagnostic`). */
    fun redactDiagnostic(text: String): String = engine.redactDiagnostic(text)

    fun setMode(mode: ProxyMode) = launchCatching(R.string.home_action_switch_mode) { engine.setMode(mode) }

    /**
     * Loads the scrub slots for a row: one per region the scene's pool covers, its fastest node, ordered by
     * [REGION_ORDER] then code; the current exit occupies its region's slot. No looping, no hard-coded list (H-P1-3).
     */
    fun prefetchSlots(scene: Scene) = viewModelScope.launch {
        val pool = runCatching { engine.sceneCandidates(scene.id, null) }.getOrDefault(emptyList())
        val byRegion = (pool + scene.selected).filter { it.id >= 0 && it.region.isNotBlank() }.groupBy { it.region.uppercase() }
        val slots = byRegion.map { (r, ns) -> ns.firstOrNull { it.id == scene.selected.id } ?: ns.minBy { it.latencyMs?.takeIf { ms -> ms >= 0 } ?: Int.MAX_VALUE } }
            .sortedWith(compareBy({ REGION_ORDER.indexOf(it.region.uppercase()).let { i -> if (i < 0) Int.MAX_VALUE else i } }, { it.region.uppercase() }))
        _ui.update { it.copy(slots = it.slots + (scene.id to slots)) }
    }

    /**
     * J-1: this row's own funnel (contract v0.7 §19.a), same freshness window as the scene candidates (设置 › 结果保留)
     * and the 200 ms slow threshold. A failure or an empty range drops the entry, so the row writes "n 个可用" again.
     */
    fun prefetchFunnel(scene: Scene) = viewModelScope.launch { refreshFunnel(scene.id) }

    private suspend fun refreshFunnel(sceneId: String) {
        val ttl = runCatching { engine.settings().first().latencyTtlHours }.getOrDefault(24).coerceAtLeast(1) * 3_600_000L
        val f = runCatching { engine.sceneFunnel(sceneId, ttl, MINI_FUNNEL_THRESHOLD_MS) }.getOrNull()
        _ui.update { it.copy(funnels = if (f != null && f.poolSize > 0) it.funnels + (sceneId to f) else it.funnels - sceneId) }
    }

    /** A candidate tapped in the scene sheet: same inline confirm as the swipe (exit IP line, 更改/取消). */
    fun pick(scene: Scene, node: NodeSummary) = launchCatching(R.string.home_action_preview_exit) {
        if (node.id == scene.selected.id) return@launchCatching
        val change = engine.previewSceneChange(scene.id, node.id)
        _ui.update { it.copy(pending = PendingChange(scene, node, change)) }
    }

    /**
     * 订阅分组 / Zephyr 优选. Choosing 优选 may move the exit to the best node; for AI that is an exit-IP change,
     * so it goes through the inline confirm first and the source is recorded only after "更改" (§14.y).
     */
    /** Scenes being re-tested (prototype 10 "检测中") and the pool scan's progress ("正在检测 138/512"). */
    private val _retesting = MutableStateFlow<Set<String>>(emptySet())
    val retesting: StateFlow<Set<String>> = _retesting.asStateFlow()
    val scan: StateFlow<com.zephyr.engine.ScanProgress?> = engine.scanProgress().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun retest(sceneId: String) {
        if (sceneId in _retesting.value) return
        _retesting.update { it + sceneId }
        launchCatching(R.string.home_action_retest) {
            kotlinx.coroutines.coroutineScope {
                // #208 bug 3: the row's funnel used to be read only when the scene's testedAt moved. A retest writes node
                // latencies but testedAt is the exit-trace time (video / custom never get one), so the funnel kept the
                // numbers from before the scan (已测速 0). Re-read it as the scan advances and once it ends.
                val watch = launch { engine.scanProgress().filterNotNull().distinctUntilChanged().collect { refreshFunnel(sceneId) } }
                try { engine.retestScene(sceneId) } finally { watch.cancel(); _retesting.update { it - sceneId } }
                refreshFunnel(sceneId)
            }
        }
    }

    fun setSource(scene: Scene, source: com.zephyr.engine.SceneSource) = launchCatching(R.string.home_action_switch_source) {
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
        if (now != null && now.id != previous) showToast(uiText(R.string.home_switched_to, now.name), scene.id, previous)
    }

    fun confirmPending() = launchCatching(R.string.home_action_switch_exit) {
        val p = _ui.value.pending ?: return@launchCatching
        val previous = p.scene.selected.id
        engine.applySceneChange(p.scene.id, p.node.id)
        p.thenSource?.let { runCatching { engine.setSceneSource(p.scene.id, it) } }
        _ui.update { it.copy(pending = null) }
        showToast(uiText(R.string.home_switched_to, p.node.name), p.scene.id, previous)
    }

    /**
     * Prototype `#gChange`: toggles the inline proposal (fastest other node), confirmed with "更改为X", plus
     * 「浏览全部节点」 to pick any node (iOS GlobalModeCard).
     */
    fun toggleGlobalChange() = launchCatching(R.string.home_action_load_nodes) {
        if (_ui.value.globalOpen || _ui.value.globalProposal != null) { _ui.update { it.copy(globalProposal = null, globalOpen = false) }; return@launchCatching }
        val cur = globalNow()
        val best = globalAlternatives(cur).firstOrNull()
        val x = best?.let { b -> runCatching { engine.previewGlobalChange(b.id) }.getOrNull() }
        _ui.update { it.copy(globalNode = cur, globalProposal = best, globalChange = x, globalOpen = true) }
    }

    /**
     * Library nodes another global exit could use, fastest first (iOS `globalAlternatives`): the candidates of every
     * pooled scene. #208: the live GLOBAL group only lists config names (negative live ids), which setGlobalNode can't
     * take, so on the real core the old GLOBAL-members-only search never found a node. GLOBAL stays the fallback (mock).
     */
    private suspend fun globalAlternatives(cur: NodeSummary?): List<NodeSummary> {
        val seen = HashSet<Long>()
        val pooled = scenes.value.ifEmpty { runCatching { engine.scenes().first() }.getOrDefault(emptyList()) }
            .filter { it.source != com.zephyr.engine.SceneSource.SUBSCRIPTION_GROUP }
        val all = pooled.flatMap { s -> runCatching { engine.sceneCandidates(s.id, null) }.getOrDefault(emptyList()) }.filter { seen.add(it.id) }
            .ifEmpty { runCatching { engine.groupMembers(com.zephyr.engine.core.CoreEngine.GLOBAL, 0, 500).rows }.getOrDefault(emptyList()).filter { it.protocol.uppercase() !in NON_NODES } }
        return all.filter { it.id >= 0 && it.id != cur?.id && it.name != cur?.name && (it.latencyMs ?: 0) >= 0 }.sortedBy { it.latencyMs ?: Int.MAX_VALUE }
    }

    fun confirmGlobal() = launchCatching(R.string.home_action_switch_node) {
        val to = _ui.value.globalProposal ?: return@launchCatching
        switchGlobal(to)
    }

    /** #208: a node picked on the nodes page (detail sheet 「用作全局节点」) becomes the global exit. */
    fun useGlobalNode(node: NodeSummary) = launchCatching(R.string.home_action_switch_node) {
        if (_ui.value.globalNode == null) runCatching { globalNow() }.getOrNull()?.let { n -> _ui.update { it.copy(globalNode = n) } }
        if (node.id == _ui.value.globalNode?.id) return@launchCatching
        switchGlobal(node)
    }

    private suspend fun switchGlobal(to: NodeSummary) {
        val from = _ui.value.globalNode
        engine.setGlobalNode(to.id)
        _ui.update { it.copy(globalProposal = null, globalOpen = false, globalNode = to) }
        showToast(uiText(R.string.home_switched_to, to.name), null, null, from?.let { f -> { engine.setGlobalNode(f.id); _ui.update { u -> u.copy(globalNode = f) } } })
    }

    private suspend fun globalNow(): NodeSummary? {
        (engine as? com.zephyr.engine.core.CoreEngine)?.globalNode()?.let { return it }
        val name = engine.policyGroups().first().firstOrNull { it.name == com.zephyr.engine.core.CoreEngine.GLOBAL }?.selected
        val rows = engine.groupMembers(com.zephyr.engine.core.CoreEngine.GLOBAL, 0, 500).rows
        return rows.firstOrNull { it.name == name } ?: connection.value.globalNodeId?.let { id -> rows.firstOrNull { it.id == id } }
    }

    fun cancelPending() = _ui.update { it.copy(pending = null) }

    fun undo() = launchCatching(R.string.home_action_undo) {
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
                    showToast(uiText(R.string.home_now_uses, plan.who, plan.node.name), null, null) { engine.setSceneException(plan.scene.id, appId, prevPin) }
                } else {
                    val prev = plan.scene.selected.id.takeIf { it >= 0 }
                    engine.applySceneChange(plan.scene.id, plan.node.id)
                    showToast(uiText(R.string.home_now_uses, plan.who, plan.node.name), plan.scene.id, prev)
                }
            }.onFailure { showToast(uiText(R.string.home_apply_failed, plan.who), null, null) }
            is com.zephyr.app.ui.command.CommandPlan.Direct -> runCatching {
                engine.overrideHost(plan.host, com.zephyr.engine.TraceTarget.DIRECT, null, persistent = true)
                showToast(uiText(R.string.home_now_direct, plan.who), null, null) {
                    engine.overrideHost(plan.host, com.zephyr.engine.TraceTarget.UNCHANGED, null, persistent = true)
                }
            }.onFailure { showToast(uiText(R.string.home_apply_failed, plan.who), null, null) }
            is com.zephyr.app.ui.command.CommandPlan.Uhd -> runCatching {
                // §15.h: the filter never moves the node by itself; a previewed (and here confirmed) suggestion does.
                val sid = plan.scene.id
                val was = plan.scene.nodeFilter
                if (plan.clear) {
                    engine.setSceneNodeFilter(sid, null)
                    showToast(uiText(R.string.home_now_all_nodes, plan.who), null, null) { engine.setSceneNodeFilter(sid, was) }
                } else {
                    engine.setSceneNodeFilter(sid, com.zephyr.engine.SceneNodeFilter.UHD)
                    val to = plan.preview?.takeIf { !it.currentKept }?.suggested
                    val prev = plan.scene.selected.id.takeIf { it >= 0 }
                    if (to != null) engine.applySceneChange(sid, to.id)
                    showToast(if (to != null) uiText(R.string.home_now_uses_uhd, plan.who, to.name) else uiText(R.string.home_now_uhd_only, plan.who), null, null) {
                        engine.setSceneNodeFilter(sid, was)
                        if (to != null && prev != null) engine.applySceneChange(sid, prev)
                    }
                }
            }.onFailure { showToast(uiText(R.string.home_apply_failed, plan.who), null, null) }
            is com.zephyr.app.ui.command.CommandPlan.NoNodes -> Unit
        }
    }

    /** Plain notice without undo (e.g. "已添加 Orbit（512 个节点）" after an import, review L-P2-12). */
    fun notify(msg: UiText) = showToast(msg, null, null)

    /** Notice with 撤销 (audit U27: a route override from the trace can be taken back like a scene change). */
    fun notifyUndo(msg: UiText, undo: suspend () -> Unit) = showToast(msg, null, null, undo)

    /** Undo window in ms; AppRoot stretches it with TalkBack's recommended timeout (review H-P2-14). */
    var toastWindowMs: Long = com.zephyr.design.tokens.ZMotion.undoWindow.toLong()

    private fun showToast(msg: UiText, sceneId: String?, prev: NodeId?, undo: (suspend () -> Unit)? = null) {
        toastJob?.cancel()
        val serial = ++toastSerial
        _ui.update { it.copy(toast = UndoToast(msg, sceneId, prev, serial, undo)) }
        toastJob = viewModelScope.launch {
            delay(toastWindowMs)
            _ui.update { if (it.toast?.serial == serial) it.copy(toast = null) else it }
        }
    }

    companion object {
        /** Group/built-in members of GLOBAL that are not exits. */
        private val NON_NODES = setOf("SELECTOR", "URLTEST", "FALLBACK", "LOADBALANCE", "RELAY", "DIRECT", "REJECT", "REJECTDROP", "PASS", "COMPATIBLE")
        const val SPARK_POINTS = 90
        /** Contract §19.a: home passes `latency.threshold-slow` (200 ms). */
        const val MINI_FUNNEL_THRESHOLD_MS = 200
        val REGION_ORDER = listOf("HK", "TW", "JP", "KR", "SG", "US", "GB", "DE", "FR", "NL", "CA", "AU")
        fun preview() = HomeViewModel(MockEngine(demo = true))
    }
}

/** One line, what happened and what to do; never a raw exception. */
internal fun errorText(@StringRes what: Int, code: com.zephyr.engine.ErrorCode?): UiText = when (code) {
    com.zephyr.engine.ErrorCode.NOT_RUNNING -> uiText(R.string.home_error_not_connected, uiText(what))
    com.zephyr.engine.ErrorCode.SUBSCRIPTION_NOT_FOUND -> uiText(R.string.home_failure_no_subscription)
    com.zephyr.engine.ErrorCode.NETWORK_UNAVAILABLE -> uiText(R.string.home_failure_network)
    com.zephyr.engine.ErrorCode.NODE_NOT_FOUND, com.zephyr.engine.ErrorCode.SCENE_NOT_FOUND -> uiText(R.string.home_error_node_gone, uiText(what))
    else -> uiText(R.string.home_error_failed, uiText(what))
}
