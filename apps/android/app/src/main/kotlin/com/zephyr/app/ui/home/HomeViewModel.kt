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
import kotlinx.coroutines.launch

@Immutable
data class PendingChange(val scene: Scene, val node: NodeSummary, val change: ExitChange)

@Immutable
data class UndoToast(val message: String, val sceneId: String?, val previousNodeId: NodeId?, val serial: Long)

@Immutable
data class HomeUi(
    val traffic: TrafficSample = TrafficSample(0, 0, 0),
    val spark: List<Float> = emptyList(),
    val now: Long = System.currentTimeMillis(),
    val usage: UsageSummary? = null,
    val pending: PendingChange? = null,
    val toast: UndoToast? = null,
    val regionIndex: Map<String, Int> = emptyMap(),
)

class HomeViewModel(private val engine: ZephyrEngine = AppGraph.engine) : ViewModel() {
    val connection: StateFlow<ConnectionState> = engine.connectionState().stateIn(viewModelScope, SharingStarted.Eagerly, ConnectionState())
    val scenes: StateFlow<List<Scene>> = engine.scenes().stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())
    val subscriptions: StateFlow<List<Subscription>> = engine.subscriptions().stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val _ui = MutableStateFlow(HomeUi())
    val ui: StateFlow<HomeUi> = _ui.asStateFlow()
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
        // 1 Hz clock for uptime; cheap and avoids per-frame recomposition.
        viewModelScope.launch { while (true) { _ui.update { it.copy(now = System.currentTimeMillis()) }; delay(1_000) } }
        viewModelScope.launch {
            connection.collectLatest { c ->
                if (c.status != ConnectionStatus.CONNECTED) return@collectLatest
                val back = engine.recentTraffic(SPARK_POINTS).map { it.downBps.toFloat() }
                _ui.update { it.copy(spark = back, traffic = engine.recentTraffic(1).lastOrNull() ?: it.traffic) }
                engine.traffic().collect { s ->
                    _ui.update { u -> u.copy(traffic = s, spark = (u.spark + s.downBps.toFloat()).takeLast(SPARK_POINTS)) }
                }
            }
        }
    }

    fun setMode(mode: ProxyMode) = viewModelScope.launch { engine.setMode(mode) }

    /** Horizontal swipe on a scene row cycles regions; shows the inline confirm with the exit-IP change. */
    fun cycleRegion(scene: Scene, forward: Boolean) = viewModelScope.launch {
        val idx = (_ui.value.regionIndex[scene.id] ?: REGIONS.indexOf(scene.selected.region).coerceAtLeast(0))
        val next = Math.floorMod(idx + if (forward) 1 else -1, REGIONS.size)
        val candidates = engine.sceneCandidates(scene.id, REGIONS[next])
        val best = candidates.firstOrNull() ?: return@launch
        val change = engine.previewSceneChange(scene.id, best.id)
        _ui.update { it.copy(pending = PendingChange(scene, best, change), regionIndex = it.regionIndex + (scene.id to next)) }
    }

    fun confirmPending() = viewModelScope.launch {
        val p = _ui.value.pending ?: return@launch
        val previous = p.scene.selected.id
        engine.applySceneChange(p.scene.id, p.node.id)
        _ui.update { it.copy(pending = null) }
        showToast("已换到 ${p.node.name}", p.scene.id, previous)
    }

    fun cancelPending() = _ui.update { it.copy(pending = null, regionIndex = emptyMap()) }

    fun undo() = viewModelScope.launch {
        val t = _ui.value.toast ?: return@launch
        if (t.sceneId != null && t.previousNodeId != null) engine.applySceneChange(t.sceneId, t.previousNodeId)
        _ui.update { it.copy(toast = null) }
    }

    fun applyCommandSwitch(sceneId: String?, nodeId: NodeId, label: String) = viewModelScope.launch {
        if (sceneId == null || sceneId == "global") {
            engine.setMode(ProxyMode.GLOBAL); engine.setGlobalNode(nodeId)
            showToast("已换到 $label", null, null)
        } else {
            val prev = scenes.value.firstOrNull { it.id == sceneId }?.selected?.id
            engine.applySceneChange(sceneId, nodeId)
            showToast("已换到 $label", sceneId, prev)
        }
    }

    private fun showToast(msg: String, sceneId: String?, prev: NodeId?) {
        toastJob?.cancel()
        val serial = ++toastSerial
        _ui.update { it.copy(toast = UndoToast(msg, sceneId, prev, serial)) }
        toastJob = viewModelScope.launch {
            delay(com.zephyr.design.tokens.ZMotion.undoWindow.toLong())
            _ui.update { if (it.toast?.serial == serial) it.copy(toast = null) else it }
        }
    }

    companion object {
        const val SPARK_POINTS = 90
        val REGIONS = listOf("SG", "JP", "US", "HK", "TW", "KR")
        fun preview() = HomeViewModel(MockEngine(demo = true))
    }
}
