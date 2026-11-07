package com.zephyr.engine.mock

import com.zephyr.engine.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.PI
import kotlin.math.sin

/**
 * Deterministic in-process engine implementing contract v0 from design/prototype data.
 * Used by previews, screenshot tests, and the app until core-mobile exposes the same calls.
 *
 * @param demo start already connected with the prototype's "2:14:07" uptime (screenshots / store art).
 */
class MockEngine(
    private val clock: () -> Long = System::currentTimeMillis,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    demo: Boolean = false,
    private val latencyScale: Double = 1.0,
    /** Where CPU-bound queries run. Tests pass Dispatchers.Unconfined so results land in the same frame. */
    private val compute: kotlinx.coroutines.CoroutineDispatcher = Dispatchers.Default,
    /** Reported query durations; tests pin it so goldens don't depend on host speed. */
    private val measure: ((Long) -> Long) = { it },
) : ZephyrEngine {

    // ── state ────────────────────────────────────────────────────────────────
    private val connection = MutableStateFlow(
        if (demo) ConnectionState(
            status = ConnectionStatus.CONNECTED,
            mode = ProxyMode.RULE,
            since = clock() - DEMO_UPTIME_MS,
            network = NetworkInfo(NetworkKind.WIFI, "家", trusted = false),
        ) else ConnectionState(network = NetworkInfo(NetworkKind.WIFI, "家", trusted = false)),
    )
    private val sceneState = MutableStateFlow(MockScenes.initial(clock()))
    private val subscriptionState = MutableStateFlow(MockSubscriptions.initial(clock()))
    private val settingsState = MutableStateFlow(Settings())
    private val groupState = MutableStateFlow(MockGroups.initial(clock()))
    private val latencyBus = MutableSharedFlow<List<LatencyUpdate>>(extraBufferCapacity = 64)
    private val tested = ConcurrentHashMap<Long, Int>()
    private val testedCount = AtomicLong(BASE_TESTED)
    private val queries = object : LinkedHashMap<Long, NodeQuery>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, NodeQuery>?) = size > 16
    }
    private val nextToken = AtomicLong(1)

    val connectionValue: StateFlow<ConnectionState> get() = connection.asStateFlow()

    // ── 1. Connection ────────────────────────────────────────────────────────
    override fun connectionState(): Flow<ConnectionState> = connection.asStateFlow()

    override suspend fun connect() {
        if (connection.value.status == ConnectionStatus.CONNECTED) return
        connection.update { it.copy(status = ConnectionStatus.CONNECTING, error = null) }
        delay(CONNECT_DELAY_MS)
        connection.update { it.copy(status = ConnectionStatus.CONNECTED, since = clock()) }
    }

    override suspend fun disconnect() {
        if (connection.value.status == ConnectionStatus.DISCONNECTED) return
        connection.update { it.copy(status = ConnectionStatus.DISCONNECTING) }
        delay(DISCONNECT_DELAY_MS)
        connection.update { it.copy(status = ConnectionStatus.DISCONNECTED, since = null) }
    }

    override suspend fun setMode(mode: ProxyMode) {
        connection.update {
            it.copy(mode = mode, globalNodeId = if (mode == ProxyMode.GLOBAL) it.globalNodeId ?: MockScenes.TOKYO_03.id else it.globalNodeId)
        }
    }

    override suspend fun setGlobalNode(id: NodeId): ExitChange {
        val from = MockScenes.byId(connection.value.globalNodeId ?: MockScenes.TOKYO_03.id) ?: MockScenes.TOKYO_03
        val to = MockScenes.byId(id) ?: catalogSummary(id)
        connection.update { it.copy(globalNodeId = id) }
        return ExitChange(
            sceneId = null,
            fromRegion = from.region, fromIp = MockScenes.exitIp(from.id),
            toRegion = to.region, toIp = MockScenes.exitIp(to.id),
            affectedApps = emptyList(), unchangedApps = emptyList(),
        )
    }

    // ── 2. Traffic ───────────────────────────────────────────────────────────
    override fun traffic(): Flow<TrafficSample> = flow {
        while (currentCoroutineContextActive()) {
            if (connection.value.status == ConnectionStatus.CONNECTED) emit(sampleAt(clock()))
            delay(1_000)
        }
    }

    override suspend fun recentTraffic(seconds: Int): List<TrafficSample> {
        val n = seconds.coerceIn(0, 300)
        val now = clock()
        return List(n) { i -> sampleAt(now - (n - 1 - i) * 1_000L) }
    }

    override suspend fun usageToday(): UsageSummary {
        val weights = LongArray(24) { MockCatalog.hsh(2, it) % 1000 + 200 }
        val sum = weights.sum()
        val hourly = weights.map { it * TODAY_BYTES / sum }.toMutableList()
        hourly[23] += TODAY_BYTES - hourly.sum()
        return UsageSummary(TODAY_BYTES, 4, 6 * 3_600_000L, 38, hourly)
    }

    // ── 3. Scenes ────────────────────────────────────────────────────────────
    override fun scenes(): Flow<List<Scene>> = sceneState.asStateFlow()

    override suspend fun sceneCandidates(sceneId: String, region: String?): List<NodeSummary> {
        requireScene(sceneId)
        return MockScenes.pool(region).withLatency()
    }

    override suspend fun previewSceneChange(sceneId: String, nodeId: NodeId): ExitChange {
        val scene = requireScene(sceneId)
        val to = MockScenes.byId(nodeId) ?: throw ZephyrException(ErrorCode.NODE_NOT_FOUND, "$nodeId")
        val (affected, unchanged) = when (scene.kind) {
            SceneKind.AI -> listOf("GPT", "Gemini") to scene.exceptions.map { it.app }
            SceneKind.VIDEO -> listOf("Netflix", "YouTube") to emptyList()
            else -> emptyList<String>() to emptyList()
        }
        return ExitChange(
            sceneId = sceneId,
            fromRegion = scene.selected.region, fromIp = scene.exitIp,
            toRegion = to.region, toIp = MockScenes.exitIp(to.id),
            affectedApps = affected, unchangedApps = unchanged,
        )
    }

    override suspend fun applySceneChange(sceneId: String, nodeId: NodeId) {
        requireScene(sceneId)
        val to = MockScenes.byId(nodeId) ?: throw ZephyrException(ErrorCode.NODE_NOT_FOUND, "$nodeId")
        sceneState.update { list ->
            list.map { if (it.id == sceneId) it.copy(selected = to, exitIp = MockScenes.exitIp(to.id), source = SceneSource.MANUAL) else it }
        }
    }

    override suspend fun setSceneException(sceneId: String, appId: String, nodeId: NodeId?) {
        requireScene(sceneId)
        val node = nodeId?.let { MockScenes.byId(it) ?: throw ZephyrException(ErrorCode.NODE_NOT_FOUND, "$it") }
        val name = Apps.name(appId)
        sceneState.update { list ->
            list.map { s ->
                if (s.id != sceneId) s
                else s.copy(exceptions = s.exceptions.filter { it.appId != appId } + listOfNotNull(node?.let { SceneException(name, it, appId) }))
            }
        }
    }

    override suspend fun retestScene(sceneId: String): Scene {
        requireScene(sceneId)
        delay(scaled(900))
        sceneState.update { list -> list.map { if (it.id == sceneId) it.copy(testedAt = clock()) else it } }
        return requireScene(sceneId)
    }

    private fun requireScene(id: String): Scene =
        sceneState.value.firstOrNull { it.id == id } ?: throw ZephyrException(ErrorCode.SCENE_NOT_FOUND, id)

    // ── 4. Policy groups ─────────────────────────────────────────────────────
    override fun policyGroups(): Flow<List<PolicyGroup>> = groupState.asStateFlow()

    override suspend fun groupMembers(group: String, offset: Int, limit: Int): NodePage {
        val g = groupState.value.firstOrNull { it.name == group } ?: throw ZephyrException(ErrorCode.GROUP_NOT_FOUND, group)
        val lim = limit.coerceIn(0, 500)
        val end = (offset + lim).coerceAtMost(g.memberCount)
        val rows = (offset until end).map { k -> MockGroups.member(group, k).let { s -> s.copy(latencyMs = latencyOf(s.id)) } }
        return NodePage(rows, offset.toLong(), g.memberCount.toLong())
    }

    override suspend fun selectInGroup(group: String, nodeId: NodeId) {
        val name = MockScenes.byId(nodeId)?.name ?: catalogSummary(nodeId).name
        groupState.update { list -> list.map { if (it.name == group) it.copy(selected = name) else it } }
    }

    override suspend fun testGroup(group: String) {
        val g = groupState.value.firstOrNull { it.name == group } ?: throw ZephyrException(ErrorCode.GROUP_NOT_FOUND, group)
        testLatency((0 until minOf(g.memberCount, 100)).map { MockGroups.member(group, it).id })
        groupState.update { list -> list.map { if (it.name == group) it.copy(testedAt = clock()) else it } }
    }

    // ── 5. Node library ──────────────────────────────────────────────────────
    override suspend fun nodeIndex(): NodeIndex {
        val q = NodeQuery.build("")
        return NodeIndex(q.total, q.sections(), testedCount.get())
    }

    override suspend fun queryNodes(query: String): NodeQueryResult = withContext(compute) {
        val t0 = System.nanoTime()
        val q = NodeQuery.build(query)
        val took = measure((System.nanoTime() - t0) / 1_000)
        val token = nextToken.getAndIncrement()
        synchronized(queries) { queries[token] = q }
        NodeQueryResult(query, q.total, q.sections(), q.highlights, took, token)
    }

    override suspend fun nodeRows(token: Long, offset: Long, limit: Int): NodePage {
        val q = synchronized(queries) { queries[token] } ?: NodeQuery.build("")
        val lim = limit.coerceIn(0, 500)
        if (q.groups.isEmpty() || offset >= q.total || lim == 0) return NodePage(emptyList(), offset, q.total)
        val end = minOf(q.total, offset + lim)
        val rows = ArrayList<NodeSummary>((end - offset).toInt())
        var gi = q.groupForOrdinal(offset)
        var ord = offset
        while (ord < end) {
            val g = q.groups[gi]
            val groupEnd = g.nodeOffset + g.count
            while (ord < end && ord < groupEnd) {
                val j = q.indexInRegion(g, ord - g.nodeOffset)
                val id = MockCatalog.idOf(g.region, j)
                rows.add(MockCatalog.summary(g.region, j, tested[id]))
                ord++
            }
            gi++
        }
        return NodePage(rows, offset, q.total)
    }

    override suspend fun node(id: NodeId): NodeDetail {
        val s = MockScenes.byId(id) ?: catalogSummary(id)
        val h = MockCatalog.hsh(7, (id and 0x7FFF_FFFF).toInt())
        return NodeDetail(
            summary = s.copy(latencyMs = latencyOf(id)),
            server = "${s.region.lowercase()}-${(h % 900 + 100)}.•••.net",
            port = 443 + (h % 3).toInt() * 1000,
            subscription = if (MockCatalog.isValid(id) && MockCatalog.indexOf(id) < 8_204) "Nebula Cloud" else "其他订阅",
        )
    }

    override suspend fun testLatency(ids: List<NodeId>) {
        val batch = ids.take(100)
        if (batch.isEmpty()) return
        // Group results into ~50 ms buckets so the UI recomposes a handful of times, not per node.
        val buckets = batch.groupBy { id -> latencyDelay(id) / 50 }
        scope.launch {
            var elapsed = 0L
            for (bucket in buckets.keys.sorted()) {
                val at = bucket * 50
                delay(scaled(at - elapsed)); elapsed = at
                val now = clock()
                val updates = buckets.getValue(bucket).map { id ->
                    val ms = testedLatencyOf(id)
                    if (tested.put(id, ms) == null) testedCount.incrementAndGet()
                    LatencyUpdate(id, ms, now)
                }
                latencyBus.emit(updates)
            }
        }
    }

    override fun latencyUpdates(): Flow<List<LatencyUpdate>> = latencyBus.asSharedFlow()

    private fun latencyDelay(id: Long): Long {
        val r = (id / MockCatalog.ID_STRIDE).toInt()
        val j = (id % MockCatalog.ID_STRIDE).toInt()
        return 80 + MockCatalog.hsh(j, r) % 321 // 80–400 ms
    }

    private fun testedLatencyOf(id: Long): Int = when {
        MockCatalog.isValid(id) -> MockCatalog.testedLatency(MockCatalog.regionOf(id), MockCatalog.indexOf(id))
        else -> MockScenes.latency(id) ?: LATENCY_TIMEOUT
    }

    private fun latencyOf(id: Long): Int? = tested[id] ?: when {
        MockCatalog.isValid(id) -> MockCatalog.cachedLatency(MockCatalog.regionOf(id), MockCatalog.indexOf(id))
        else -> MockScenes.latency(id)
    }

    private fun List<NodeSummary>.withLatency() = map { it.copy(latencyMs = latencyOf(it.id)) }.sortedBy { it.latencyMs?.takeIf { l -> l >= 0 } ?: Int.MAX_VALUE }

    private fun catalogSummary(id: Long): NodeSummary {
        if (!MockCatalog.isValid(id)) throw ZephyrException(ErrorCode.NODE_NOT_FOUND, "$id")
        return MockCatalog.summary(MockCatalog.regionOf(id), MockCatalog.indexOf(id), tested[id])
    }

    // ── 6. Rules ─────────────────────────────────────────────────────────────
    override suspend fun ruleStats(): RuleStats = RuleStats(MockRules.TOTAL, MockRules.LAYERS, compiled = true, diskBytes = MockRules.DISK_BYTES)

    override suspend fun testRule(input: String): RuleTrace {
        val q = MockRules.normalise(input)
        if (q.isEmpty() || q.any { it.isWhitespace() }) throw ZephyrException(ErrorCode.RULE_INPUT_INVALID, input)
        val hit = MockRules.match(q)
        val took = 10L + q.length
        val scenes = sceneState.value
        return if (hit != null) {
            val scene = MockRules.sceneIdFor(hit.policy)?.let { id -> scenes.firstOrNull { it.id == id } }
            RuleTrace(
                input = q, isIp = MockRules.isIp(q), layerIndex = hit.layer, rule = hit.rule, ruleNo = hit.ruleNo,
                policy = scene?.id ?: hit.policy, scene = scene, exitIp = scene?.exitIp, tookMicros = took,
            )
        } else {
            val other = scenes.firstOrNull { it.id == "other" }
            RuleTrace(q, MockRules.isIp(q), null, "MATCH", null, "other", other, other?.exitIp, took)
        }
    }

    // ── 7. Subscriptions ─────────────────────────────────────────────────────
    override fun subscriptions(): Flow<List<Subscription>> = subscriptionState.asStateFlow()

    override suspend fun subscriptionsSummary(): SubscriptionsSummary =
        SubscriptionsSummary(MockSubscriptions.TOTAL_COUNT + subscriptionState.value.size - 2, MockCatalog.TOTAL + subscriptionState.value.drop(2).sumOf { it.nodeCount })

    override suspend fun importSubscription(source: ImportSource, payload: String): Subscription {
        val p = payload.trim()
        if (p.isEmpty()) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "empty")
        if (source == ImportSource.URL || source == ImportSource.CLIPBOARD) {
            if (!(p.startsWith("https://") || p.startsWith("http://") || p.startsWith("clash://") || p.startsWith("zephyr://"))) {
                throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "not a subscription link")
            }
        }
        delay(scaled(800))
        val h = MockCatalog.hsh(11, p.hashCode() and 0x7FFF_FFFF)
        val name = runCatching { java.net.URI(p).host?.substringBeforeLast('.')?.substringAfterLast('.')?.replaceFirstChar { it.uppercase() } }.getOrNull()
            ?: "新订阅"
        val sub = Subscription(
            id = "sub-${h.toString(16)}", name = name, url = MockSubscriptions.redact(p),
            nodeCount = 120 + h % 600, totalBytes = 200_000_000_000L, usedBytes = 0, remainingBytes = 200_000_000_000L,
            expiresAt = clock() + 30L * DAY_MS, updatedAt = clock(), autoUpdateHours = settingsState.value.autoUpdateHours,
        )
        subscriptionState.update { it + sub }
        return sub
    }

    override suspend fun previewUpdate(id: String): SubscriptionDiff {
        val s = subscriptionState.value.firstOrNull { it.id == id } ?: throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, id)
        delay(scaled(500))
        return MockSubscriptions.diffFor(s)
    }

    override suspend fun updateSubscription(id: String): SubscriptionDiff {
        val diff = previewUpdate(id)
        subscriptionState.update { list ->
            list.map { if (it.id == id) it.copy(updatedAt = clock(), lastDiff = diff, nodeCount = it.nodeCount + diff.addedNodes - diff.removedNodes) else it }
        }
        return diff
    }

    override suspend fun updateAll(): List<SubscriptionDiff> = subscriptionState.value.map { updateSubscription(it.id) }

    override suspend fun deleteSubscription(id: String) {
        subscriptionState.update { list -> list.filterNot { it.id == id } }
    }

    // ── 8. Connections, logs, settings ───────────────────────────────────────
    override fun activeConnections(): Flow<List<ConnectionInfo>> = flow {
        val start = clock()
        while (currentCoroutineContextActive()) {
            val t = (clock() - start) / 1000
            emit(if (connection.value.status == ConnectionStatus.CONNECTED) MockConnections.at(start, t) else emptyList())
            delay(1_000)
        }
    }

    override fun recentHosts(limit: Int): Flow<List<ConnectionInfo>> = flow {
        val start = clock()
        while (currentCoroutineContextActive()) {
            emit(MockConnections.at(start, (clock() - start) / 1000).take(minOf(limit, 5).coerceAtLeast(0)))
            delay(1_000)
        }
    }

    private val overrides = java.util.concurrent.ConcurrentHashMap<String, TraceOverride>()

    override suspend fun connectionTrace(host: String): ConnectionTrace =
        MockConnections.trace(host, clock())?.copy(override = overrides[host])
            ?: throw ZephyrException(ZephyrError(ErrorCode.NODE_NOT_FOUND, host))

    override suspend fun overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Boolean) {
        if (MockConnections.trace(host, clock()) == null) throw ZephyrException(ZephyrError(ErrorCode.NODE_NOT_FOUND, host))
        if (target == TraceTarget.UNCHANGED) overrides.remove(host) else overrides[host] = TraceOverride(target, sceneId, persistent)
    }

    override suspend fun closeConnection(id: String) = Unit
    override suspend fun closeAll() = Unit

    override fun logs(minLevel: LogLevel): Flow<LogLine> = flow {
        var i = 0
        while (currentCoroutineContextActive()) {
            val line = MockLogs.line(i++, clock())
            if (line.level >= minLevel) emit(line)
            delay(scaled(700 + MockCatalog.hsh(5, i) % 900))
        }
    }.flowOn(compute)

    override fun settings(): Flow<Settings> = settingsState.asStateFlow()
    override suspend fun updateSettings(patch: Settings) { settingsState.value = patch }
    override suspend fun storage(): StorageInfo = StorageInfo(600_000_000L, 1_900_000_000L, 3_100_000_000L)

    // ── 9. Command search ────────────────────────────────────────────────────
    override suspend fun commandSuggestions(input: String): List<CommandSuggestion> =
        MockCommands.suggest(input, sceneState.value, connection.value)

    // ── helpers ──────────────────────────────────────────────────────────────
    private fun sampleAt(at: Long): TrafficSample {
        val t = (at / 1000).toInt()
        val wave = sin(t * 2 * PI / 37.0) * 0.5 + 0.5
        val jitter = (MockCatalog.hsh(1, t) % 1000) / 1000.0
        val down = 2_400_000 + ((wave * 0.7 + jitter * 0.3) * 1_000_000).toLong()
        val up = 150_000 + ((MockCatalog.hsh(1, t + 7) % 1000) * 110L)
        return TrafficSample(at, up, down)
    }

    private fun scaled(ms: Long): Long = (ms * latencyScale).toLong()
    private fun scaled(ms: Int): Long = scaled(ms.toLong())

    private suspend fun currentCoroutineContextActive() = kotlin.coroutines.coroutineContext.isActive

    companion object {
        const val DEMO_UPTIME_MS = (2 * 3600 + 14 * 60 + 7) * 1000L
        const val CONNECT_DELAY_MS = 600L
        const val DISCONNECT_DELAY_MS = 250L
        const val TODAY_BYTES = 1_800_000_000L
        const val BASE_TESTED = 41_280L
        const val DAY_MS = 86_400_000L
    }
}
