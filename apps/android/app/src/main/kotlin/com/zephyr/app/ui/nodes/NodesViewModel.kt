package com.zephyr.app.ui.nodes

import androidx.collection.LruCache
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zephyr.app.di.AppGraph
import com.zephyr.engine.NodeId
import com.zephyr.engine.NodeQueryResult
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.RegionSection
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first

/** A virtual row: header of [section] or the [ordinal]-th matched node (0-based across sections). */
sealed interface NodeRow {
    data class Header(val section: RegionSection) : NodeRow
    data class Node(val ordinal: Long, val section: RegionSection) : NodeRow
}

@Immutable
data class NodesUi(
    val query: String = "",
    val result: NodeQueryResult? = null,
    val total: Long = 0,
    val regionCount: Int = 0,
    /** Region chips: the index's largest sections, top 8 by count (review L-P1-4). */
    val chips: List<Pair<String, Long>> = emptyList(),
    val subscriptionCount: Int = 0,
    val testedCount: Long = 0,
)

/**
 * Drives the 10^7–10^8-row list: never holds more than [CACHE_PAGES] × [PAGE] summaries in memory,
 * maps row → (section, ordinal) by binary search, fetches pages on demand.
 */
@OptIn(FlowPreview::class)
class NodesViewModel(private val engine: ZephyrEngine = AppGraph.engine) : ViewModel() {
    private val _ui = MutableStateFlow(NodesUi())
    val ui: StateFlow<NodesUi> = _ui.asStateFlow()
    private val queryFlow = MutableStateFlow<String?>(null)

    private val pages = LruCache<Long, List<NodeSummary>>(CACHE_PAGES)
    private val inflight = HashSet<Long>()
    /** Bumped when a page lands so visible rows recompose; reading it subscribes. */
    val pageEpoch = mutableIntStateOf(0)
    val latency = mutableStateMapOf<NodeId, Int>()
    val testing = mutableStateMapOf<NodeId, Boolean>()
    private var token = 0L
    private var testJob: Job? = null

    init {
        viewModelScope.launch {
            val idx = engine.nodeIndex()
            val chips = idx.sections.filter { it.count > 0 }.sortedByDescending { it.count }.take(8).map { it.region to it.count }
            val subs = runCatching { engine.subscriptions().first().size }.getOrDefault(0)
            _ui.value = _ui.value.copy(total = idx.total, regionCount = idx.sections.size, testedCount = idx.testedCount, chips = chips, subscriptionCount = subs)
        }
        viewModelScope.launch {
            queryFlow.debounce(80).distinctUntilChanged().collect { q -> if (q != null && q != lastRun) launchRun(q) }
        }
        viewModelScope.launch {
            engine.latencyUpdates().collect { batch ->
                batch.forEach { u -> latency[u.id] = u.latencyMs; testing.remove(u.id) }
                _ui.value = _ui.value.copy(testedCount = _ui.value.testedCount + batch.size)
            }
        }
    }

    /** [composing]: an IME is mid-composition, so show the text but don't query half-typed letters (review L-P2-5). */
    fun setQuery(q: String, immediate: Boolean = false, composing: Boolean = false) {
        _ui.value = _ui.value.copy(query = q)
        if (composing) return
        queryFlow.value = q
        if (immediate) launchRun(q)
    }

    // One query in flight at a time: a chip tap and the debounced text query used to race, and a slower earlier
    // result could land last and overwrite the newer one (review L-P2-4).
    private var runJob: Job? = null
    private var lastRun: String? = null
    private fun launchRun(q: String) {
        runJob?.cancel()
        lastRun = q
        runJob = viewModelScope.launch { run(q) }
    }

    private suspend fun run(q: String) {
        val r = engine.queryNodes(q)
        kotlinx.coroutines.currentCoroutineContext().ensureActive() // superseded by a newer query
        token = r.token
        pages.evictAll(); inflight.clear()
        _ui.value = _ui.value.copy(result = r)
        pageEpoch.intValue++
    }

    fun rowAt(row: Int): NodeRow? {
        val r = _ui.value.result ?: return null
        val secs = r.sections
        if (secs.isEmpty()) return null
        var lo = 0; var hi = secs.size - 1
        while (lo < hi) { val m = (lo + hi + 1) ushr 1; if (secs[m].rowOffset <= row) lo = m else hi = m - 1 }
        val s = secs[lo]
        val k = row - s.rowOffset
        if (k == 0L) return NodeRow.Header(s)
        val before = secs.subList(0, lo).sumOf { it.count }
        return NodeRow.Node(before + k - 1, s)
    }

    /** Section a row belongs to (for the pinned header and the rail bubble). */
    fun sectionAt(row: Int): RegionSection? = when (val r = rowAt(row)) {
        is NodeRow.Header -> r.section
        is NodeRow.Node -> r.section
        null -> null
    }

    /** Pure read, safe during composition; pages are fetched by [prefetch] (review L-P2-6). */
    fun node(ordinal: Long): NodeSummary? {
        val page = ordinal / PAGE
        return pages[page]?.getOrNull((ordinal - page * PAGE).toInt())
    }

    /** Load the pages covering visible [rows] plus one ahead; called from a LaunchedEffect, never from composition. */
    fun prefetch(rows: IntRange) {
        if (rows.isEmpty()) return
        val ords = rows.mapNotNull { (rowAt(it) as? NodeRow.Node)?.ordinal }
        if (ords.isEmpty()) return
        val first = ords.min() / PAGE
        val last = ords.max() / PAGE
        for (p in first..last + 1) if (pages[p] == null) load(p)
    }

    private fun load(page: Long) {
        if (!inflight.add(page)) return
        val t = token
        viewModelScope.launch {
            val res = engine.nodeRows(t, page * PAGE, PAGE)
            if (t == token) { pages.put(page, res.rows); pageEpoch.intValue++ }
            inflight.remove(page)
        }
    }

    /** Called 400 ms after scrolling settles with the visible node ids (≤ 100). */
    fun testVisible(ids: List<NodeId>) {
        val todo = ids.filter { latency[it] == null && testing[it] == null }.take(100)
        if (todo.isEmpty()) return
        todo.forEach { testing[it] = true }
        testJob = viewModelScope.launch { engine.testLatency(todo) }
    }

    companion object {
        const val PAGE = 200
        const val CACHE_PAGES = 24
    }
}
