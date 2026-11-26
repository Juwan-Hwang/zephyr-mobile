package com.zephyr.app.ui.groups

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiText
import com.zephyr.app.ui.home.errorText
import com.zephyr.engine.ConnectionStatus
import com.zephyr.engine.GroupType
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.PolicyGroup
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Which policy groups the page lists and which the user may change (pure; unit-tested). */
object PolicyGroupList {
    /** Groups Zephyr injects for scenes and their per-app pins ("Zephyr·AI", "Zephyr·AI·Claude"); scene cards own them. */
    private const val SCENE_PREFIX = "Zephyr·"

    /** The subscription's own groups in config order; GLOBAL is already left out by the engine (contract §4). */
    fun visible(groups: List<PolicyGroup>): List<PolicyGroup> =
        groups.filter { !it.name.startsWith(SCENE_PREFIX) && it.name != com.zephyr.engine.core.CoreEngine.GLOBAL }

    /** Only select groups take a manual choice; url-test / fallback / load-balance / relay pick their own member. */
    fun selectable(g: PolicyGroup): Boolean = g.type == GroupType.SELECT
}

/**
 * #208: the subscription's policy groups (contract §4 「代理」页) — policyGroups, groupMembers, selectInGroup,
 * testGroup. The groups only exist while the core runs, so the page asks to connect first.
 */
class GroupsViewModel(private val engine: ZephyrEngine = AppGraph.engine) : ViewModel() {
    data class Members(val group: PolicyGroup, val rows: List<NodeSummary>, val loading: Boolean = true, val testing: Boolean = false)

    val connected: StateFlow<Boolean> = engine.connectionState().map { it.status == ConnectionStatus.CONNECTED }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)
    /** Null until the first read. */
    val groups: StateFlow<List<PolicyGroup>?> = engine.policyGroups().map(PolicyGroupList::visible)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _open = MutableStateFlow<Members?>(null)
    val open: StateFlow<Members?> = _open.asStateFlow()
    private val _notices = MutableSharedFlow<UiText>(extraBufferCapacity = 4)
    val notices: SharedFlow<UiText> = _notices.asSharedFlow()

    fun open(g: PolicyGroup) {
        _open.value = Members(g, emptyList())
        viewModelScope.launch { load(g.name) }
    }

    fun close() { _open.value = null }

    private suspend fun load(group: String) {
        val rows = try { engine.groupMembers(group, 0, MAX_MEMBERS).rows } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
            _notices.tryEmit(errorText(R.string.home_action_load_nodes, (e as? com.zephyr.engine.ZephyrException)?.error?.code)); emptyList()
        }
        _open.update { m -> if (m?.group?.name == group) m.copy(rows = rows, loading = false) else m }
    }

    fun select(node: NodeSummary) {
        val m = _open.value ?: return
        if (!PolicyGroupList.selectable(m.group) || node.name == m.group.selected) return
        viewModelScope.launch {
            try {
                engine.selectInGroup(m.group.name, node.id)
                _open.update { cur -> if (cur?.group?.name == m.group.name) cur.copy(group = cur.group.copy(selected = node.name)) else cur }
                _notices.tryEmit(uiText(R.string.home_switched_to, node.name))
            } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
                _notices.tryEmit(errorText(R.string.home_action_switch_node, (e as? com.zephyr.engine.ZephyrException)?.error?.code))
            }
        }
    }

    fun test() {
        val m = _open.value ?: return
        if (m.testing) return
        _open.update { it?.copy(testing = true) }
        viewModelScope.launch {
            try { engine.testGroup(m.group.name) } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
                _notices.tryEmit(errorText(R.string.home_action_retest, (e as? com.zephyr.engine.ZephyrException)?.error?.code))
            }
            load(m.group.name)
            _open.update { cur -> if (cur?.group?.name == m.group.name) cur.copy(testing = false) else cur }
        }
    }

    companion object {
        /** Contract §4: one groupMembers page (limit ≤ 500). */
        const val MAX_MEMBERS = 500
    }
}
