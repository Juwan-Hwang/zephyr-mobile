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
    private val demo: Boolean = false,
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
    // Demo keeps the prototype's trusted network; a real first install starts empty (audit #208 U7).
    // Review And-6: demo settings match the prototype / iOS fixture (本地代理端口 7890, 无需密码).
    private val settingsState = MutableStateFlow(
        if (demo) Settings(trustedWifi = listOf("家"), disconnectOnTrusted = true, localProxyAuth = false) else Settings(),
    )
    private val groupState = MutableStateFlow(MockGroups.initial(clock()))
    private val latencyBus = MutableSharedFlow<List<LatencyUpdate>>(extraBufferCapacity = 64)
    private val tested = ConcurrentHashMap<Long, Int>()
    private val testedCount = AtomicLong(BASE_TESTED)
    /** Contract §18.a mock: write time of each `tested` sample; fixture (cached) latencies count as written at start. */
    private val testedAt = ConcurrentHashMap<Long, Long>()
    private val startedAt = clock()
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

    override suspend fun previewGlobalChange(nodeId: NodeId): ExitChange {
        val from = MockScenes.byId(connection.value.globalNodeId ?: MockScenes.TOKYO_03.id) ?: MockScenes.TOKYO_03
        val to = MockScenes.byId(nodeId) ?: catalogSummary(nodeId)
        return ExitChange(null, from.region, MockScenes.exitIp(from.id), to.region, MockScenes.exitIp(to.id))
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
        val out = List(n) { i -> sampleAt(now - (n - 1 - i) * 1_000L) }
        // Review And-6: in demo the newest reading is the prototype's home "2.8 MB/s ↓ · 194 KB/s ↑" (iOS
        // MockFixtures.prototypeSample), so the two platforms' home screenshots compare value for value.
        return if (demo && out.isNotEmpty()) out.dropLast(1) + TrafficSample(out.last().at, PROTOTYPE_UP_BPS, PROTOTYPE_DOWN_BPS) else out
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
        val scene = requireScene(sceneId)
        return MockScenes.pool(region).filter { scene.nodeFilter == null || isUhd(it) }.withLatency()
    }

    /** §15.h mock: 4K by name, candidates = the unfiltered mock pool of the current region. */
    override suspend fun previewSceneNodeFilter(sceneId: String, filter: SceneNodeFilter): NodeFilterPreview {
        val scene = requireScene(sceneId)
        val region = scene.selected.region.takeIf { scene.selected.id >= 0 }
        val all = MockScenes.pool(region).withLatency()
        val keep = all.filter(::isUhd)
        val kept = scene.selected.id < 0 || isUhd(scene.selected)
        val suggested = if (kept) null else keep.filter { it.latencyMs != null }.minByOrNull { it.latencyMs!! }
        return NodeFilterPreview(
            matching = keep.size, total = all.size, poolMatching = keep.size.toLong(), currentKept = kept,
            suggested = suggested, change = suggested?.let { previewSceneChange(sceneId, it.id) },
        )
    }

    override suspend fun setSceneNodeFilter(sceneId: String, filter: SceneNodeFilter?) {
        val scene = requireScene(sceneId)
        if (filter != null) {
            val region = scene.selected.region.takeIf { scene.selected.id >= 0 }
            if (MockScenes.pool(region).none(::isUhd)) throw ZephyrException(ErrorCode.RULE_INPUT_INVALID, "no 4K node in region") // = core MobileError.Invalid
        }
        sceneState.update { list -> list.map { if (it.id == sceneId) it.copy(nodeFilter = filter) else it } }
    }

    private fun isUhd(n: NodeSummary) = UHD.containsMatchIn(n.name)

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

    override suspend fun setSceneSource(sceneId: String, source: SceneSource): NodeSummary? {
        requireScene(sceneId)
        sceneState.update { list -> list.map { if (it.id == sceneId) it.copy(source = source) else it } }
        return null
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
        // Mirrors the real scan's 64-node batches over a 512-node pool so the home row's bar has something to show.
        try {
            for (done in 0..512 step 64) { scan.value = ScanProgress(done, 512); if (done < 512) delay(scaled(110)) }
        } finally { scan.value = null }
        sceneState.update { list -> list.map { if (it.id == sceneId) it.copy(testedAt = clock()) else it } }
        return requireScene(sceneId)
    }

    private val scan = MutableStateFlow<ScanProgress?>(null)
    override fun scanProgress(): Flow<ScanProgress?> = scan.asStateFlow()

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
        // Contract §18.a mock: reachable / tested from one nodeFunnel over the mock latency table, same window as core.
        val ttl = settingsState.value.latencyTtlHours.coerceAtLeast(1) * 3_600_000L
        val f = nodeFunnel(ttl, 200)
        return NodeIndex(q.total, q.sections(), testedCount.get(), reachableCount = f.reachable, funnelTested = f.tested)
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
                    testedAt[id] = now
                    LatencyUpdate(id, ms, now)
                }
                latencyBus.emit(updates)
            }
        }
    }

    override fun latencyUpdates(): Flow<List<LatencyUpdate>> = latencyBus.asSharedFlow()

    /**
     * Contract §15.c mock: sourceCount / poolSize are the prototype lede (2 / 512); the pool takes the first 512
     * nodes round-robin across regions and counts their mock latencies (tested first, else cached). Same as iOS.
     */
    override suspend fun nodeFunnel(maxAgeMs: Long, thresholdMs: Int): NodeFunnel {
        val threshold = if (thresholdMs > 0) thresholdMs else 300
        var t = 0L; var ok = 0L; var under = 0L
        val now = clock()
        val n = MockCatalog.REGIONS.size
        for (i in 0 until FUNNEL_POOL) {
            val r = i % n; val j = i / n
            val id = MockCatalog.idOf(r, j)
            val live = tested[id]
            val ms = live ?: MockCatalog.cachedLatency(r, j) ?: continue
            // Contract §18.a: expired samples count neither as tested nor reachable (maxAgeMs ≤ 0 = no expiry).
            val at = if (live != null) testedAt[id] ?: startedAt else startedAt
            if (maxAgeMs > 0 && now - at > maxAgeMs) continue
            t++
            if (ms >= 0) { ok++; if (ms < threshold) under++ }
        }
        return NodeFunnel(FUNNEL_SOURCES, FUNNEL_POOL.toLong(), t, ok, under, threshold)
    }

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

    /** Same §15 rules as core for url / qr / clipboard (contract: Mock must reject what core rejects). */
    override suspend fun importSubscription(source: ImportSource, payload: String): Subscription {
        val p = payload.trim()
        if (p.isEmpty()) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "empty")
        if (source == ImportSource.FILE || (source == ImportSource.CLIPBOARD && ImportPayloads.looksLikeConfig(p))) return addMock(p, null, null)
        val items = try { ImportPayloads.parse(p).items } catch (e: ImportPayloadException) {
            throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, e.message ?: "invalid")
        }
        var first: Subscription? = null
        for (it in items) { val s = addMock(it.url, it.name, it.autoUpdateHours); if (first == null) first = s }
        return first!!
    }

    override suspend fun importItem(source: ImportSource, item: ImportItem): Subscription = addMock(item.url.trim(), item.name, item.autoUpdateHours)

    private suspend fun addMock(p: String, name: String?, autoHours: Int?): Subscription {
        delay(scaled(800))
        val h = MockCatalog.hsh(11, p.hashCode() and 0x7FFF_FFFF)
        val id = "sub-${h.toString(16)}"
        subscriptionState.value.firstOrNull { it.id == id }?.let { return it } // same link: core dedupes too
        val host = runCatching { java.net.URI(p).host?.substringBeforeLast('.')?.substringAfterLast('.')?.replaceFirstChar { it.uppercase() } }.getOrNull()
        val sub = Subscription(
            id = id, name = name ?: host ?: "新订阅", url = MockSubscriptions.redact(p),
            nodeCount = 120 + h % 600, totalBytes = 200_000_000_000L, usedBytes = 0, remainingBytes = 200_000_000_000L,
            expiresAt = clock() + 30L * DAY_MS, updatedAt = clock(), autoUpdateHours = autoHours ?: settingsState.value.autoUpdateHours,
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

    // §16.g ①: fixed demo credential; reset hands out a fresh one in the same format.
    @Volatile private var proxyCredential = MOCK_CREDENTIAL
    override suspend fun localProxyCredential(): String = proxyCredential
    override suspend fun resetLocalProxyCredential(): String =
        com.zephyr.engine.core.LocalProxyCredential.generate().also { proxyCredential = it }

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
        /** Contract §16.g ① Mock value (24 characters after `zephyr:`). */
        const val MOCK_CREDENTIAL = "zephyr:mockmockmockmockmockmock"
        const val DEMO_UPTIME_MS = (2 * 3600 + 14 * 60 + 7) * 1000L
        const val CONNECT_DELAY_MS = 600L
        const val DISCONNECT_DELAY_MS = 250L
        const val TODAY_BYTES = 1_800_000_000L
        const val PROTOTYPE_DOWN_BPS = 2_800_000L
        const val PROTOTYPE_UP_BPS = 194_000L
        const val BASE_TESTED = 41_280L
        const val FUNNEL_SOURCES = 2
        const val FUNNEL_POOL = 512
        const val DAY_MS = 86_400_000L
    }
}

/** §15.h 4K by name: ASCII-only case-insensitive (no UNICODE_CASE, so full-width ４Ｋ does not match). Checked against contract/fixtures/uhd-names-v1.json. */
internal fun isUhdName(name: String): Boolean = UHD.containsMatchIn(name)

private val UHD = Regex("4[Kk]|[Uu][Hh][Dd]|8[Kk]") // 契约 §15.h：仅 ASCII 折叠（U+212A 不算）
