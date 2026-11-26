package com.zephyr.app.ui.home

import androidx.compose.runtime.Immutable
import com.zephyr.app.R
import com.zephyr.app.ui.common.NodeSort
import com.zephyr.app.ui.common.NodeSortPref
import com.zephyr.app.ui.common.NodeSorting
import com.zephyr.app.ui.groups.PolicyGroupList
import com.zephyr.engine.ConnectionState
import com.zephyr.engine.NodeId
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.PolicyGroup
import com.zephyr.engine.ProxyMode
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Which policy group Home's 「节点」 row controls (pure; unit-tested).
 *
 * Rule mode: the subscription's main select group — the one its final `MATCH` rule sends traffic to when that is a
 * select group, otherwise the first select group in config order. Zephyr's own scene / pin groups and GLOBAL are left
 * out, as on the 策略组 page.
 */
object MainGroup {
    /** Select groups the sheet offers, main group first, the rest in config order. */
    fun selectGroups(groups: List<PolicyGroup>, finalPolicy: String?): List<PolicyGroup> {
        val sel = PolicyGroupList.visible(groups).filter(PolicyGroupList::selectable)
        val main = sel.firstOrNull { it.name == finalPolicy } ?: sel.firstOrNull() ?: return emptyList()
        return listOf(main) + sel.filter { it.name != main.name }
    }

    fun main(groups: List<PolicyGroup>, finalPolicy: String?): PolicyGroup? = selectGroups(groups, finalPolicy).firstOrNull()

    /**
     * The group's choice followed down through nested groups: `["香港节点", "HK 01"]` when the main group chose the group
     * 香港节点 and that one chose HK 01. Stops at a node, an unknown name or a loop.
     */
    fun chain(group: PolicyGroup, all: List<PolicyGroup>): List<String> {
        val byName = all.associateBy { it.name }
        val out = ArrayList<String>()
        val seen = hashSetOf(group.name)
        var cur = group.selected
        while (cur != null && out.size < MAX_DEPTH) {
            out += cur
            val g = byName[cur] ?: break
            if (!seen.add(g.name)) break
            cur = g.selected
        }
        return out
    }

    /** Row text: the node, or 「组名 › 节点名」 when the choice is itself a group. */
    fun label(chain: List<String>): String? = when (chain.size) {
        0 -> null
        1 -> chain[0]
        else -> "${chain.first()} › ${chain.last()}"
    }

    private const val MAX_DEPTH = 8
}

/** Home's node row and its sheet. */
@Immutable
data class NodePickerUi(
    val mode: ProxyMode = ProxyMode.RULE,
    /** Row text; null = nothing chosen yet / unknown (drawn as "—"). */
    val label: String? = null,
    val latencyMs: Int? = null,
    /** The sheet is open. */
    val open: Boolean = false,
    /** Rule mode: the select groups on offer, main first. Empty in global mode. */
    val groups: List<String> = emptyList(),
    /** Rule mode: the group the sheet shows. */
    val group: String? = null,
    /** The current member of [group] (rule) or the global node (global). */
    val selectedName: String? = null,
    val selectedId: NodeId? = null,
    /** Rows as the subscription (or the library) orders them. */
    val raw: List<NodeSummary> = emptyList(),
    /** [raw] in the chosen order, re-sorted on load, sort change and when a test ends — never under the finger. */
    val rows: List<NodeSummary> = emptyList(),
    /** Global mode: nodes matching the search (the sheet loads the first [NodePicker.GLOBAL_LIMIT]). */
    val total: Long = 0,
    /** Names of rows that are groups themselves (no region badge). */
    val groupNames: Set<String> = emptySet(),
    val latency: Map<NodeId, Int> = emptyMap(),
    val loading: Boolean = false,
    val testing: Boolean = false,
    val query: String = "",
    val sort: NodeSort = NodeSort.DEFAULT,
    /** Rule mode without a running core: groups only exist while connected. */
    val offline: Boolean = false,
) {
    /** Search shows once the list is long. */
    val searchable: Boolean get() = query.isNotEmpty() || (if (mode == ProxyMode.GLOBAL) total else rows.size.toLong()) > SEARCH_FROM

    /** Rows after the search (rule mode filters here; global mode asks the engine). */
    val visibleRows: List<NodeSummary> get() =
        if (mode == ProxyMode.GLOBAL || query.isBlank()) rows else rows.filter { it.name.contains(query.trim(), ignoreCase = true) }

    fun isCurrent(n: NodeSummary): Boolean =
        if (mode == ProxyMode.GLOBAL) n.id == selectedId || (selectedId == null && n.name == selectedName) else PolicyGroupList.isCurrent(n, selectedName)

    companion object { const val SEARCH_FROM = 20 }
}

/**
 * Drives [NodePickerUi] for Home: the row follows the main group's choice (rule) or the global exit (global); the sheet
 * lists the group's members (rule) or the library (global, live member ids are not valid for setGlobalNode) and
 * switches on one tap. [onSwitched] shows 「已切换至 X」 with undo; [onError] the usual failure toast.
 */
class NodePicker(
    private val engine: ZephyrEngine,
    private val scope: CoroutineScope,
    connection: StateFlow<ConnectionState>,
    private val onSwitched: (name: String, undo: (suspend () -> Unit)?) -> Unit,
    private val onError: (what: Int, e: Throwable) -> Unit,
    private val currentGlobal: suspend () -> NodeSummary?,
    private val switchGlobal: suspend (NodeSummary) -> Unit,
) {
    private val _ui = MutableStateFlow(NodePickerUi())
    val ui: StateFlow<NodePickerUi> = _ui.asStateFlow()
    private var groupsNow: List<PolicyGroup> = emptyList()
    private var finalPolicy: String? = null
    /** Rule-mode row text from the last time the groups were readable (they vanish while disconnected). */
    private var lastRuleLabel: String? = null
    private var loadJob: Job? = null
    private var searchJob: Job? = null

    init {
        scope.launch { NodeSortPref.flow.distinctUntilChanged().collect { s -> _ui.update { it.copy(sort = s, rows = sorted(it.raw, s, it.latency)) } } }
        scope.launch {
            combine(connection.map { it.mode to it.globalNodeId }.distinctUntilChanged(), engine.policyGroups()) { m, g -> m to g }
                .collectLatest { (m, groups) ->
                    groupsNow = groups
                    if (m.first == ProxyMode.GLOBAL) refreshGlobalRow() else refreshRuleRow(groups)
                }
        }
        scope.launch {
            engine.latencyUpdates().collect { batch ->
                if (batch.isEmpty()) return@collect
                _ui.update { u ->
                    val lat = u.latency + batch.associate { it.id to it.latencyMs }
                    val cur = u.selectedId?.let { lat[it] } ?: u.rows.firstOrNull { u.isCurrent(it) }?.let { lat[it.id] }
                    u.copy(latency = lat, latencyMs = if (u.mode == ProxyMode.GLOBAL && cur != null) cur else u.latencyMs)
                }
            }
        }
    }

    private suspend fun refreshRuleRow(groups: List<PolicyGroup>) {
        if (groups.isNotEmpty() && finalPolicy == null) finalPolicy = runCatching { engine.finalPolicy() }.getOrNull()
        val offer = MainGroup.selectGroups(groups, finalPolicy)
        val main = offer.firstOrNull()
        val chain = main?.let { MainGroup.chain(it, groups) }.orEmpty()
        if (groups.isNotEmpty()) lastRuleLabel = MainGroup.label(chain)
        _ui.update { u ->
            val keep = u.group?.takeIf { g -> offer.any { it.name == g } }
            u.copy(
                mode = ProxyMode.RULE, groups = offer.map { it.name }, offline = groups.isEmpty(),
                label = if (groups.isEmpty()) lastRuleLabel else MainGroup.label(chain),
                group = keep ?: main?.name,
                selectedName = offer.firstOrNull { it.name == (keep ?: main?.name) }?.selected,
                selectedId = null,
            )
        }
        // The leaf's reading comes from its own group's members (the main group's when it chose a node directly).
        if (main != null && chain.isNotEmpty()) {
            val parent = if (chain.size >= 2) chain[chain.size - 2] else main.name
            val ms = runCatching { engine.groupMembers(parent, 0, MEMBER_LIMIT).rows }.getOrNull()?.firstOrNull { PolicyGroupList.isCurrent(it, chain.last()) }?.latencyMs
            _ui.update { it.copy(latencyMs = ms) }
        } else _ui.update { it.copy(latencyMs = null) }
        if (_ui.value.open && !_ui.value.loading && _ui.value.rows.isEmpty()) load()
    }

    private suspend fun refreshGlobalRow() {
        val n = runCatching { currentGlobal() }.getOrNull()
        val ms = n?.latencyMs ?: n?.let { runCatching { engine.node(it.id).latencyMs }.getOrNull() }
        _ui.update { it.copy(mode = ProxyMode.GLOBAL, label = n?.name, latencyMs = ms, selectedId = n?.id, selectedName = n?.name, groups = emptyList(), group = null, offline = false) }
    }

    fun open() {
        _ui.update { it.copy(open = true, query = "", raw = emptyList(), rows = emptyList()) }
        load()
    }

    fun close() {
        loadJob?.cancel(); searchJob?.cancel()
        _ui.update { it.copy(open = false, loading = false, testing = false, query = "") }
    }

    fun chooseGroup(name: String) {
        if (name == _ui.value.group) return
        _ui.update { u -> u.copy(group = name, selectedName = groupsNow.firstOrNull { it.name == name }?.selected, raw = emptyList(), rows = emptyList(), query = "") }
        load()
    }

    fun setSort(sort: NodeSort) {
        _ui.update { it.copy(sort = sort, rows = sorted(it.raw, sort, it.latency)) }
        NodeSortPref.set(sort)
    }

    fun setQuery(q: String) {
        _ui.update { it.copy(query = q) }
        if (_ui.value.mode != ProxyMode.GLOBAL) return
        searchJob?.cancel()
        searchJob = scope.launch { delay(SEARCH_DEBOUNCE_MS); load() }
    }

    private fun load() {
        loadJob?.cancel()
        val u = _ui.value
        _ui.update { it.copy(loading = true) }
        loadJob = scope.launch {
            try {
                if (u.mode == ProxyMode.GLOBAL) {
                    val q = engine.queryNodes(u.query.trim())
                    val rows = if (q.total > 0) engine.nodeRows(q.token, 0, GLOBAL_LIMIT).rows else emptyList()
                    _ui.update { it.copy(raw = rows, rows = sorted(rows, it.sort, it.latency), total = q.total, groupNames = emptySet(), loading = false) }
                } else {
                    val g = u.group
                    if (g == null) { _ui.update { it.copy(raw = emptyList(), rows = emptyList(), loading = false) }; return@launch }
                    val rows = engine.groupMembers(g, 0, MEMBER_LIMIT).rows
                    val names = groupsNow.map { it.name }.toSet()
                    _ui.update { it.copy(raw = rows, rows = sorted(rows, it.sort, it.latency), groupNames = rows.map { r -> r.name }.filter { n -> n in names }.toSet(), loading = false) }
                }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
                _ui.update { it.copy(loading = false) }
                onError(R.string.home_action_load_nodes, e)
            }
        }
    }

    /** Header 测速: the group (rule, testGroup) or the listed nodes (global, testLatency); results arrive on latencyUpdates. */
    fun test() {
        val u = _ui.value
        if (u.testing || u.loading) return
        _ui.update { it.copy(testing = true) }
        scope.launch {
            try {
                if (u.mode == ProxyMode.GLOBAL) engine.testLatency(u.rows.map { it.id }.filter { it >= 0 })
                else u.group?.let { g ->
                    engine.testGroup(g)
                    // Readings for members the stream did not carry (mock, core cache) come with a fresh read.
                    val fresh = runCatching { engine.groupMembers(g, 0, MEMBER_LIMIT).rows }.getOrNull()
                    if (fresh != null) _ui.update { cur -> if (cur.group == g) cur.copy(raw = fresh, latency = cur.latency - fresh.map { it.id }.toSet()) else cur }
                }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
                onError(R.string.home_action_retest, e)
            } finally {
                _ui.update { it.copy(testing = false, rows = sorted(it.raw, it.sort, it.latency)) }
            }
            if (u.mode != ProxyMode.GLOBAL) refreshRuleRow(groupsNow) // the row's reading after the group test
        }
    }

    /** One tap switches, closes the sheet and shows 「已切换至 X」 with undo. No confirmation step. */
    fun pick(n: NodeSummary) {
        val u = _ui.value
        if (u.isCurrent(n)) { close(); return }
        close()
        scope.launch {
            try {
                if (u.mode == ProxyMode.GLOBAL) {
                    switchGlobal(n)
                    _ui.update { it.copy(label = n.name, selectedId = n.id, selectedName = n.name, latencyMs = it.latency[n.id] ?: n.latencyMs) }
                } else {
                    val g = u.group ?: return@launch
                    val prev = u.rows.firstOrNull { u.isCurrent(it) }
                    engine.selectInGroup(g, n.id)
                    applyLocal(g, n.name)
                    val undo: (suspend () -> Unit)? = if (prev == null) null else ({ engine.selectInGroup(g, prev.id); applyLocal(g, prev.name) })
                    onSwitched(n.name, undo)
                }
            } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Throwable) {
                onError(R.string.home_action_switch_node, e)
            }
        }
    }

    /** Shows the new choice at once; the next policyGroups poll confirms it. */
    private suspend fun applyLocal(group: String, member: String) {
        groupsNow = groupsNow.map { if (it.name == group) it.copy(selected = member) else it }
        refreshRuleRow(groupsNow)
    }

    private fun sorted(rows: List<NodeSummary>, sort: NodeSort, lat: Map<NodeId, Int>) =
        NodeSorting.sort(rows, sort) { lat[it.id] ?: it.latencyMs }

    companion object {
        /** Contract §4: one groupMembers page (limit ≤ 500). */
        const val MEMBER_LIMIT = 500
        /** Global mode lists this many library nodes; search narrows the rest. */
        const val GLOBAL_LIMIT = 300
        const val SEARCH_DEBOUNCE_MS = 200L
    }
}
