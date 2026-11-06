package com.zephyr.engine.core

import com.zephyr.core.mobile.MobileCore
import com.zephyr.core.mobile.MobileException
import com.zephyr.core.mobile.DnsConfig
import com.zephyr.core.mobile.FetchedSubscription
import com.zephyr.core.mobile.RuntimeOptions
import com.zephyr.core.mobile.TunConfig
import com.zephyr.core.mobile.TunStackKind
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.map
import com.zephyr.core.mobile.SceneKind as CoreSceneKind
import com.zephyr.core.mobile.SceneSource as CoreSceneSource
import com.zephyr.core.mobile.TraceTarget as CoreTraceTarget
import kotlinx.coroutines.flow.filterNotNull
import com.zephyr.core.mobile.ProxyMode as CoreMode
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ImportSource
import com.zephyr.engine.Subscription
import com.zephyr.engine.SubscriptionsSummary
import com.zephyr.engine.LayerKind
import com.zephyr.engine.NodeIndex
import com.zephyr.engine.NodePage
import com.zephyr.engine.NodeQueryResult
import com.zephyr.engine.NodeSummary
import com.zephyr.engine.RegionSection
import com.zephyr.engine.RuleLayer
import com.zephyr.engine.RuleStats
import com.zephyr.engine.RuleTrace
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.ZephyrError
import com.zephyr.engine.ZephyrException
import com.zephyr.engine.mock.MockCatalog
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.merge
import com.zephyr.engine.*
import kotlinx.coroutines.withContext
import com.zephyr.core.mobile.LayerKind as CoreLayerKind
import com.zephyr.core.mobile.NodeRow as CoreRow
import com.zephyr.core.mobile.RegionSection as CoreSection

/**
 * Engine backed by the Rust core (core-mobile via UniFFI). Node index/search/rows and rule tests go to
 * [MobileCore] once it has data; everything else (and every call when the native library is absent,
 * e.g. JVM screenshot tests or builds without `-Pzephyr.rust=true`) stays on [fallback].
 *
 * Threading: UniFFI calls are blocking FFI; they run on [io] so the main thread never touches JNA.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CoreEngine(
    private val fallback: ZephyrEngine,
    private val dataDir: String? = null,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    /**
     * Whether [fallback]'s synthetic catalogue may stand in for an empty native store. True for debug,
     * screenshots and tests; false in release, where an empty store means "no subscription yet" and the
     * UI shows its empty state instead of fake nodes.
     */
    private val mockData: Boolean = true,
    /** mihomo's REST controller while the embedded core runs, else null (VPN off, tests, screenshots). */
    private val live: () -> LivePort? = { null },
    private val tick: Long = 1_000,
    private val clock: () -> Long = System::currentTimeMillis,
    private val fetcher: (String) -> SubscriptionFetcher.Fetched = SubscriptionFetcher::httpFetch,
) : ZephyrEngine by fallback {

    private val core: MobileCore? = dataDir?.let { dir ->
        try { MobileCore(dir) } catch (_: Throwable) { null } // UnsatisfiedLinkError / missing .so → mock
    }

    /** True when the native core is loaded (not necessarily populated). */
    val isNative: Boolean get() = core != null

    @Volatile private var nodesReady: Boolean? = null
    @Volatile private var rulesReady: Boolean? = null

    private suspend fun nodes(): MobileCore? {
        val c = core ?: return null
        nodesReady?.let { return if (it) c else null }
        val ok = withContext(io) { runCatching { c.nodeIndex().total > 0uL }.getOrDefault(false) }
        nodesReady = ok
        return if (ok) c else null
    }

    private suspend fun rules(): MobileCore? {
        val c = core ?: return null
        rulesReady?.let { return if (it) c else null }
        val ok = withContext(io) { runCatching { c.ruleStats().total > 0uL }.getOrDefault(false) }
        rulesReady = ok
        return if (ok) c else null
    }

    /** Builds the deterministic mock catalogue inside the native store (dev/demo only). */
    suspend fun seedMockNodes(scale: Double) {
        val c = core ?: return
        withContext(io) { wrap { c.rebuildMockNodes(scale) } }
        nodesReady = null
    }

    // ── Subscriptions (core-mobile owns parsing/storage; the platform only fetches) ──────────────────
    private val subsState = kotlinx.coroutines.flow.MutableStateFlow<List<Subscription>?>(null)
    private val realSubs: Boolean get() = core != null || !mockData

    private suspend fun refreshSubs(): List<Subscription> {
        val c = core ?: return emptyList<Subscription>().also { subsState.value = it }
        return withContext(io) { wrap { c.subscriptions() }.map(::sub) }.also { subsState.value = it }
    }

    override fun subscriptions(): Flow<List<Subscription>> =
        if (!realSubs) fallback.subscriptions()
        else flow { if (subsState.value == null) refreshSubs(); emitAll(subsState.filterNotNull()) }

    override suspend fun subscriptionsSummary(): SubscriptionsSummary {
        val c = core ?: return if (mockData) fallback.subscriptionsSummary() else SubscriptionsSummary(0, 0)
        return withContext(io) { wrap { c.subscriptionsSummary() } }.let { SubscriptionsSummary(it.count.toInt(), it.totalNodes.toLong()) }
    }

    override suspend fun importSubscription(source: ImportSource, payload: String): Subscription {
        val c = core ?: return fallback.importSubscription(source, payload)
        val p = payload.trim()
        if (p.isEmpty()) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "empty")
        val isUrl = p.startsWith("https://") || p.startsWith("http://")
        if ((source == ImportSource.URL || source == ImportSource.QR) && !isUrl) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "not a subscription link")
        return withContext(io) {
            val got = if (isUrl) {
                runCatching { fetcher(p) }.getOrElse { throw ZephyrException(ErrorCode.SUBSCRIPTION_FETCH_FAILED, it.message ?: "fetch failed") }
            } else SubscriptionFetcher.Fetched(p, null, null)
            val name = got.fileName?.substringBeforeLast('.')?.takeIf { it.isNotBlank() } ?: defaultName(p, isUrl)
            val hours = runCatching { fallback.settings().first().autoUpdateHours }.getOrDefault(12)
            val s = wrap { c.importSubscription(name, if (isUrl) p else null, FetchedSubscription(got.body, got.userInfo, clock()), hours, null) }
            nodesReady = null
            if (activeSubscription() == null) setActiveSubscription(s.id)
            refreshSubs()
            sub(s)
        }
    }

    override suspend fun updateSubscription(id: String): SubscriptionDiff {
        val c = core ?: return fallback.updateSubscription(id)
        return withContext(io) {
            val url = wrap { c.subscriptionFetchUrl(id) } ?: throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "local profile")
            val got = runCatching { fetcher(url) }.getOrElse { throw ZephyrException(ErrorCode.SUBSCRIPTION_FETCH_FAILED, it.message ?: "fetch failed") }
            val d = wrap { c.updateSubscription(id, FetchedSubscription(got.body, got.userInfo, clock()), null) }
            nodesReady = null; refreshSubs(); diff(d)
        }
    }

    override suspend fun previewUpdate(id: String): SubscriptionDiff {
        val c = core ?: return fallback.previewUpdate(id)
        return withContext(io) {
            val url = wrap { c.subscriptionFetchUrl(id) } ?: throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "local profile")
            val got = runCatching { fetcher(url) }.getOrElse { throw ZephyrException(ErrorCode.SUBSCRIPTION_FETCH_FAILED, it.message ?: "fetch failed") }
            diff(wrap { c.previewSubscriptionUpdate(id, FetchedSubscription(got.body, got.userInfo, clock())) })
        }
    }

    override suspend fun updateAll(): List<SubscriptionDiff> {
        val c = core ?: return fallback.updateAll()
        val ids = withContext(io) { wrap { c.subscriptions() }.filter { it.url != null }.map { it.id } }
        return ids.mapNotNull { runCatching { updateSubscription(it) }.getOrNull() }
    }

    /**
     * Background refresh: updates every subscription whose auto-update interval has elapsed. When the
     * active one changed while the core runs, the runtime config is rebuilt and hot-reloaded.
     * Returns the ids that updated; failures are left for the next run (core keeps them due).
     */
    suspend fun updateDue(): List<String> {
        val c = core ?: return emptyList()
        val due = withContext(io) { wrap { c.dueSubscriptions(clock()) } }
        val done = due.filter { runCatching { updateSubscription(it) }.isSuccess }
        if (activeSubscription() in done) runCatching { reloadIfRunning() }
        return done
    }

    override suspend fun deleteSubscription(id: String) {
        val c = core ?: return fallback.deleteSubscription(id)
        withContext(io) { wrap { c.deleteSubscription(id) } }
        nodesReady = null
        val left = refreshSubs()
        if (activeSubscription() == id) setActiveSubscription(left.firstOrNull()?.id)
    }

    // ── Runtime config for the embedded mihomo (TunBridge.Embedded) ─────────────────────────────────
    private val activeFile: java.io.File? = dataDir?.let { java.io.File(it, "active-subscription") }
    fun activeSubscription(): String? = activeFile?.takeIf { it.isFile }?.readText()?.trim()?.ifEmpty { null }
    fun setActiveSubscription(id: String?) {
        val f = activeFile ?: return
        if (id == null) f.delete() else { val t = java.io.File(f.parentFile, ".${f.name}.tmp"); t.writeText(id); t.renameTo(f) }
    }

    /**
     * mihomo YAML for the active subscription with Zephyr's settings and the system TUN fd, or null when
     * there is nothing to run (no native core / no subscription). Control plane: unix socket only.
     */
    suspend fun runtimeConfig(tunFd: Int?, controllerSocket: String, settings: Settings, mode: ProxyMode): String? {
        val c = core ?: return null
        val id = activeSubscription() ?: refreshSubs().firstOrNull()?.id ?: return null
        val opts = RuntimeOptions(
            dns = DnsConfig(settings.dns.fakeIp, settings.dns.nameservers, settings.dns.fallback, settings.dns.ipv6),
            tun = TunConfig(
                stack = when (settings.tun.stack) { TunStack.SYSTEM -> TunStackKind.SYSTEM; TunStack.GVISOR -> TunStackKind.GVISOR; TunStack.MIXED -> TunStackKind.MIXED },
                mtu = settings.tun.mtu, ipv6 = settings.tun.ipv6, strictRoute = settings.tun.strictRoute, fileDescriptor = tunFd,
            ),
            mode = when (mode) { ProxyMode.RULE -> CoreMode.RULE; ProxyMode.GLOBAL -> CoreMode.GLOBAL; ProxyMode.DIRECT -> CoreMode.DIRECT },
            controllerSocket = controllerSocket, findProcess = true, logLevel = "warning",
        )
        return withContext(io) { wrap { c.runtimeConfig(id, opts) } }
    }

    private fun sub(s: com.zephyr.core.mobile.Subscription) = Subscription(
        id = s.id, name = s.name, url = s.url, nodeCount = s.nodeCount, usedBytes = s.usedBytes, totalBytes = s.totalBytes,
        remainingBytes = s.remainingBytes, expiresAt = s.expiresAt, updatedAt = s.updatedAt, autoUpdateHours = s.autoUpdateHours,
        lastDiff = s.lastDiff?.let(::diff),
    )

    private fun diff(d: com.zephyr.core.mobile.SubscriptionDiff) =
        SubscriptionDiff(d.addedNodes, d.removedNodes, d.ruleChanges, d.overridesKept, d.scenesRetested)

    private fun defaultName(p: String, isUrl: Boolean): String {
        if (!isUrl) return "本地配置"
        val host = runCatching { java.net.URI(p).host }.getOrNull() ?: return "新订阅"
        val parts = host.split('.').filter { it.isNotEmpty() }
        return (if (parts.size >= 2) parts[parts.size - 2] else parts.firstOrNull() ?: "新订阅").replaceFirstChar { it.uppercase() }
    }

    // ── Live mihomo (scenes, policy groups, connections, mode, delay) ───────────────────────────────
    private val names = java.util.concurrent.ConcurrentHashMap<Long, String>()
    private val liveLatency = kotlinx.coroutines.flow.MutableSharedFlow<List<LatencyUpdate>>(extraBufferCapacity = 8)

    /** Emits whether the live controller is reachable; re-checked every few ticks. */
    private val liveFlag: Flow<Boolean> = flow { while (true) { emit(live() != null); delay(tick * 2) } }.distinctUntilChanged()

    /** [real] while mihomo runs, otherwise [mock] (debug) or [empty] (release). */
    private fun <T> switching(real: (LivePort) -> Flow<T>, mock: () -> Flow<T>, empty: T): Flow<T> =
        liveFlag.flatMapLatest { on -> live()?.takeIf { on }?.let(real) ?: if (mockData) mock() else flowOf(empty) }

    private fun <T> polling(r: LivePort, every: Long, read: (LivePort) -> T): Flow<T> = flow {
        while (true) { runCatching { read(r) }.onSuccess { emit(it) }; delay(every) }
    }.flowOn(io)

    private fun summary(name: String, type: String?, latency: Int?): NodeSummary {
        val id = LiveNames.idOf(name).also { names[it] = name }
        if (name == "DIRECT") return NodeSummary(id, "直连", "CN", protocol = "DIRECT")
        return NodeSummary(id = id, name = name, region = LiveNames.regionOf(name), protocol = type?.uppercase() ?: "", latencyMs = latency?.takeIf { it > 0 })
    }

    // ── Scenes (core-mobile owns pools, selection, exceptions; mihomo hot-switches) ─────────────────
    private val scenesBump = kotlinx.coroutines.flow.MutableStateFlow(0)

    /**
     * Set by the VPN layer while the embedded core runs: rebuilds the runtime config with the live tun fd
     * and calls `zm_reload`. Needed when a scene change / exception / override alters the config.
     */
    @Volatile var reloader: (suspend () -> String?)? = null

    private suspend fun reloadIfRunning() {
        val r = reloader ?: return
        r()?.let { throw ZephyrException(ErrorCode.CORE_CRASHED, it) }
    }

    override fun scenes(): Flow<List<Scene>> = flow {
        val c = nodes()
        if (c == null) { emitAll(if (mockData) fallback.scenes() else flowOf(emptyList())); return@flow }
        // Re-read on every bump (apply/retest) and on a slow tick (selection, exits and latencies move underneath).
        emitAll(merge(scenesBump, flow { while (true) { delay(tick * 5); emit(0) } }).map {
            withContext(io) { wrap { c.scenes(clock()) } }.map(::scene)
        }.distinctUntilChanged())
    }

    override suspend fun sceneCandidates(sceneId: String, region: String?): List<NodeSummary> {
        val c = nodes() ?: return if (mockData) fallback.sceneCandidates(sceneId, region) else emptyList()
        return withContext(io) { sceneCall { c.sceneCandidates(sceneId, region, clock()) } }.map { row(it.row).copy(latencyMs = it.latencyMs.takeIf { ms -> ms > 0 }) }
    }

    override suspend fun previewSceneChange(sceneId: String, nodeId: NodeId): ExitChange {
        val c = nodes() ?: return fallback.previewSceneChange(sceneId, nodeId)
        val x = withContext(io) { sceneCall { c.previewSceneChange(sceneId, nodeId.toULong()) } }
        return ExitChange(x.sceneId, x.fromRegion ?: "", x.fromIp, x.toRegion, x.toIp, x.affectedApps, x.unchangedApps)
    }

    override suspend fun applySceneChange(sceneId: String, nodeId: NodeId) {
        val c = nodes() ?: return fallback.applySceneChange(sceneId, nodeId)
        val a = withContext(io) { sceneCall { c.applySceneChange(sceneId, nodeId.toULong(), clock()) } }
        val l = live()
        when {
            l == null -> Unit // not running: the next start picks it up from the runtime config
            !a.needsReload -> withContext(io) { liveCall(ErrorCode.SCENE_NOT_FOUND) { l.select(a.group, a.member) } }
            else -> reloadIfRunning()
        }
        scenesBump.value++
    }

    override suspend fun retestScene(sceneId: String): Scene {
        val c = nodes() ?: return fallback.retestScene(sceneId)
        val group = withContext(io) { wrap { c.scenes(clock()) } }.firstOrNull { it.id == sceneId }?.group ?: throw ZephyrException(ErrorCode.SCENE_NOT_FOUND, sceneId)
        live()?.let { l -> runCatching { withContext(io) { l.test(group, LivePort.TEST_URL, 5_000) } } }
        scenesBump.value++
        return withContext(io) { wrap { c.scenes(clock()) } }.firstOrNull { it.id == sceneId }?.let(::scene) ?: throw ZephyrException(ErrorCode.SCENE_NOT_FOUND, sceneId)
    }

    /** A scene's exit died and core switched it to the next hot-standby node (already applied in mihomo). */
    data class SceneFailoverEvent(val sceneId: String, val sceneName: String, val failed: String, val now: String, val previous: NodeId?)
    private val failoverEvents = kotlinx.coroutines.flow.MutableSharedFlow<SceneFailoverEvent>(extraBufferCapacity = 8)
    val failovers: kotlinx.coroutines.flow.SharedFlow<SceneFailoverEvent> = failoverEvents

    /**
     * One probe round (contract §14 场景自动切换): for every scene that owns traffic, test its mihomo group and
     * report whether the currently selected member answered. Name-agnostic: success is read off the group's own
     * `selected` member, so cross-subscription renames don't matter. Core decides (threshold/cooldown) and
     * returns a hot-standby switch, which we apply with selectInGroup — no reload, no dropped connections.
     */
    suspend fun probeScenes(): List<SceneFailoverEvent> {
        val c = nodes() ?: return emptyList()
        val l = live() ?: return emptyList()
        val scenes = withContext(io) { wrap { c.scenes(clock()) } }.filter { it.selected != null }
        if (scenes.isEmpty()) return emptyList()
        val groups = withContext(io) { runCatching { l.groups() }.getOrDefault(emptyList()) }.associateBy { it.name }
        val out = mutableListOf<SceneFailoverEvent>()
        for (sc in scenes) {
            val sel = groups[sc.group]?.selected ?: continue
            val ok = withContext(io) { runCatching { l.test(sc.group, LivePort.TEST_URL, 5_000) }.getOrNull() }
                ?.firstOrNull { it.name == sel }?.latencyMs?.let { it > 0 } ?: false
            val f = withContext(io) { runCatching { c.reportSceneProbe(sc.id, ok, clock()) }.getOrNull() } ?: continue
            withContext(io) { runCatching { l.select(f.apply.group, f.apply.member) } }
            val e = SceneFailoverEvent(sc.id, sc.name, f.failed.name, f.apply.member, f.apply.previous?.toLong())
            out += e; failoverEvents.tryEmit(e)
        }
        if (out.isNotEmpty()) scenesBump.value++
        return out
    }

    private val unselected = NodeSummary(id = -1, name = "未选择", region = "", protocol = "")

    private fun scene(s: com.zephyr.core.mobile.Scene) = Scene(
        id = s.id,
        kind = when (s.kind) { CoreSceneKind.AI -> SceneKind.AI; CoreSceneKind.VIDEO -> SceneKind.VIDEO; CoreSceneKind.OTHER -> SceneKind.OTHER; CoreSceneKind.CUSTOM -> SceneKind.CUSTOM },
        name = s.name, available = s.available,
        selected = s.selected?.let { row(it).copy(latencyMs = s.selectedLatencyMs?.takeIf { ms -> ms > 0 }) } ?: unselected,
        exitIp = s.exitIp,
        source = when (s.source) { CoreSceneSource.AUTO -> SceneSource.AUTO; CoreSceneSource.MANUAL -> SceneSource.MANUAL; CoreSceneSource.SUBSCRIPTION_GROUP -> SceneSource.SUBSCRIPTION_GROUP },
        testedAt = s.testedAt, note = s.note,
        exceptions = s.exceptions.mapNotNull { e -> e.node?.let { SceneException(e.app, row(it)) } },
    )

    private inline fun <T> sceneCall(block: () -> T): T = try { block() } catch (e: MobileException) {
        throw ZephyrException(ZephyrError(if (e is MobileException.NotFound) ErrorCode.SCENE_NOT_FOUND else code(e), e.message ?: e.javaClass.simpleName))
    }

    override fun policyGroups(): Flow<List<PolicyGroup>> = switching({ r ->
        polling(r, tick * 3) { p -> p.groups().map { PolicyGroup(it.name, it.type, it.selected, it.memberCount, it.testedAt) } }.distinctUntilChanged()
    }, { fallback.policyGroups() }, emptyList())

    override suspend fun groupMembers(group: String, offset: Int, limit: Int): NodePage {
        val r = live() ?: return fallback.groupMembers(group, offset, limit)
        return withContext(io) {
            val total = liveCall { r.groups() }.firstOrNull { it.name == group }?.memberCount ?: throw ZephyrException(ErrorCode.GROUP_NOT_FOUND, group)
            val rows = liveCall(ErrorCode.GROUP_NOT_FOUND) { r.members(group, offset, limit.coerceIn(0, 500)) }.map { summary(it.name, it.type, it.latencyMs) }
            NodePage(rows, offset.toLong(), total.toLong())
        }
    }

    override suspend fun selectInGroup(group: String, nodeId: NodeId) {
        val r = live() ?: return fallback.selectInGroup(group, nodeId)
        val name = names[nodeId] ?: throw ZephyrException(ErrorCode.NODE_NOT_FOUND, nodeId.toString())
        withContext(io) { liveCall(ErrorCode.GROUP_NOT_FOUND) { r.select(group, name) } }
    }

    override suspend fun testGroup(group: String) {
        val r = live() ?: return fallback.testGroup(group)
        val res = withContext(io) { liveCall(ErrorCode.GROUP_NOT_FOUND) { r.test(group, LivePort.TEST_URL, 5_000) } }
        val now = clock()
        liveLatency.tryEmit(res.map { LatencyUpdate(LiveNames.idOf(it.name).also { id -> names[id] = it.name }, it.latencyMs ?: -1, now) })
    }

    override fun latencyUpdates(): Flow<List<LatencyUpdate>> = merge(fallback.latencyUpdates(), liveLatency)

    override suspend fun setMode(mode: ProxyMode) {
        live()?.let { r -> withContext(io) { liveCall { r.setMode(mode.name.lowercase()) } } }
        fallback.setMode(mode)
    }

    override fun traffic(): Flow<TrafficSample> = switching({ _ ->
        flow { while (true) { Mihomo.traffic()?.let { emit(TrafficSample(clock(), it.upBps, it.downBps)) }; delay(tick) } }.flowOn(io)
    }, { fallback.traffic() }, TrafficSample(0, 0, 0))

    private fun conn(c: LivePort.Conn) = ConnectionInfo(
        id = c.id, host = c.host, app = c.app, scene = c.scene, node = if (c.node == "DIRECT") "直连" else c.node,
        upBytes = c.up, downBytes = c.down, startedAt = c.startedAt,
    )

    override fun activeConnections(): Flow<List<ConnectionInfo>> =
        switching({ r -> polling(r, tick) { it.connections(200).map(::conn) } }, { fallback.activeConnections() }, emptyList())

    override suspend fun closeConnection(id: String) { live()?.let { r -> withContext(io) { liveCall { r.close(id) } } } ?: fallback.closeConnection(id) }
    override suspend fun closeAll() { live()?.let { r -> withContext(io) { liveCall { r.closeAll() } } } ?: fallback.closeAll() }

    override fun recentHosts(limit: Int): Flow<List<ConnectionInfo>> = switching({ r ->
        polling(r, tick) { p ->
            p.hosts(limit.coerceIn(0, 50)).map { h ->
                // ConnectionInfo is the contract's row type for "最近连接"; total bytes go in downBytes.
                ConnectionInfo(id = h.host, host = h.host, scene = h.scene, node = if (h.node == "DIRECT") "直连" else h.node, upBytes = 0, downBytes = h.totalBytes, startedAt = h.lastSeenAt)
            }
        }
    }, { fallback.recentHosts(limit) }, emptyList())

    override suspend fun connectionTrace(host: String): ConnectionTrace {
        val r = live() ?: return fallback.connectionTrace(host)
        val t = withContext(io) { liveCall { r.trace(host) } }
        val direct = t.node == "DIRECT"
        return ConnectionTrace(
            host = t.host, lastSeenAt = t.lastSeenAt, connections = t.connections, totalBytes = t.totalBytes, rule = t.rule,
            scene = t.scene, node = if (direct) null else summary(t.node, null, null),
            via = t.chain.drop(1).dropLast(1).takeIf { it.isNotEmpty() }?.joinToString(" · "),
        )
    }

    override suspend fun overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Boolean) {
        val c = core ?: return fallback.overrideHost(host, target, sceneId, persistent)
        val t = when (target) { TraceTarget.UNCHANGED -> CoreTraceTarget.UNCHANGED; TraceTarget.DIRECT -> CoreTraceTarget.DIRECT; TraceTarget.SCENE -> CoreTraceTarget.SCENE }
        withContext(io) { sceneCall { c.overrideHost(host, t, sceneId, persistent) } }
        reloadIfRunning()
    }

    private inline fun <T> liveCall(notFound: ErrorCode = ErrorCode.NODE_NOT_FOUND, block: () -> T): T = try { block() } catch (e: MobileException) {
        throw ZephyrException(ZephyrError(if (e is MobileException.NotFound) notFound else code(e), e.message ?: e.javaClass.simpleName))
    }

    // ── Nodes ──────────────────────────────────────────────────────────────────────────────────────
    override suspend fun nodeIndex(): NodeIndex {
        val c = nodes() ?: return if (mockData) fallback.nodeIndex() else NodeIndex(0, emptyList(), 0)
        val tested = fallback.nodeIndex().testedCount
        return withContext(io) { wrap { c.nodeIndex() }.let { NodeIndex(it.total.toLong(), it.sections.map(::section), tested) } }
    }

    private val queries = java.util.concurrent.ConcurrentHashMap<Long, String>()
    private val remapped = java.util.concurrent.ConcurrentHashMap<Long, Long>()

    override suspend fun queryNodes(query: String): NodeQueryResult {
        val c = nodes() ?: return if (mockData) fallback.queryNodes(query) else NodeQueryResult(query, 0, emptyList(), emptyList(), 0, 0)
        return withContext(io) {
            wrap { c.queryNodes(query) }.also { queries[it.token.toLong()] = query }.let {
                NodeQueryResult(it.query, it.total.toLong(), it.sections.map(::section), it.highlights, it.tookMicros.toLong(), it.token.toLong())
            }
        }
    }

    override suspend fun nodeRows(token: Long, offset: Long, limit: Int): NodePage {
        val c = nodes() ?: return if (mockData) fallback.nodeRows(token, offset, limit) else NodePage(emptyList(), offset, 0)
        return withContext(io) {
            val t = remapped[token] ?: token
            val p = try { c.nodeRows(t.toULong(), offset.toULong(), limit.toUInt()) } catch (e: MobileException.StaleToken) {
                // Store was rebuilt under the list (subscription update): re-run the same query once, keep scrolling.
                val q = queries[token] ?: throw ZephyrException(ErrorCode.STALE_TOKEN, e.message ?: "stale")
                val fresh = wrap { c.queryNodes(q) }.token.toLong()
                queries[fresh] = q; remapped[token] = fresh
                wrap { c.nodeRows(fresh.toULong(), offset.toULong(), limit.toUInt()) }
            } catch (e: MobileException) { wrap { throw e } }
            p.let { p ->
                NodePage(p.rows.map(::row), p.offset.toLong(), p.total.toLong())
            }
        }
    }

    // ── Rules ──────────────────────────────────────────────────────────────────────────────────────
    override suspend fun ruleStats(): RuleStats {
        val c = rules() ?: return if (mockData) fallback.ruleStats() else RuleStats(0, emptyList(), compiled = false, diskBytes = 0)
        return withContext(io) {
            c.ruleStats().let { s ->
                RuleStats(
                    total = s.total.toLong(),
                    layers = s.layers.map { RuleLayer(it.index.toInt(), kind(it.kind), it.name, it.count.toLong(), it.note) },
                    compiled = true,
                    diskBytes = s.diskBytes.toLong(),
                )
            }
        }
    }

    override suspend fun testRule(input: String): RuleTrace {
        val c = rules() ?: return fallback.testRule(input)
        val t = withContext(io) { wrap { c.testRule(input) } }
        // Scene/exit enrichment is a UI concern the core doesn't own: resolve the policy against live scenes.
        val scene = fallback.scenes().first().firstOrNull { it.name.equals(t.policy, ignoreCase = true) || it.id.equals(t.policy, ignoreCase = true) }
        return RuleTrace(
            input = t.input, isIp = t.isIp, layerIndex = t.layerIndex?.toInt(), rule = t.rule,
            ruleNo = t.ruleNo?.toLong(), policy = t.policy, scene = scene, exitIp = null, tookMicros = t.tookMicros.toLong(),
        )
    }

    // ── Mapping ────────────────────────────────────────────────────────────────────────────────────
    private fun section(s: CoreSection) = RegionSection(s.region, regionName(s.region), s.count.toLong(), s.rowOffset.toLong())

    private fun row(r: CoreRow) = NodeSummary(
        id = r.id.toLong(), name = r.name, region = r.region, city = r.city, carrier = r.carrier,
        tag = r.tag, protocol = r.protocol, multiplier = r.multiplier,
    )

    private fun kind(k: CoreLayerKind) = when (k) {
        CoreLayerKind.OVERRIDE -> LayerKind.OVERRIDE
        CoreLayerKind.SUBSCRIPTION -> LayerKind.SUBSCRIPTION
        CoreLayerKind.DOMAIN -> LayerKind.DOMAIN
        CoreLayerKind.IP -> LayerKind.IP
    }

    private inline fun <T> wrap(block: () -> T): T = try { block() } catch (e: MobileException) {
        throw ZephyrException(ZephyrError(code(e), e.message ?: e.javaClass.simpleName))
    }

    private fun code(e: MobileException) = when (e) {
        is MobileException.NotFound -> ErrorCode.NODE_NOT_FOUND
        is MobileException.Invalid, is MobileException.RuleInputInvalid -> ErrorCode.RULE_INPUT_INVALID
        is MobileException.SubscriptionInvalid -> ErrorCode.SUBSCRIPTION_INVALID
        is MobileException.SubscriptionNotFound -> ErrorCode.SUBSCRIPTION_NOT_FOUND
        is MobileException.StaleToken -> ErrorCode.STALE_TOKEN
        is MobileException.NotRunning -> ErrorCode.NOT_RUNNING
        is MobileException.Cancelled -> ErrorCode.CANCELLED
        else -> ErrorCode.INTERNAL
    }

    companion object {
        private val NAMES: Map<String, String> = MockCatalog.REGIONS.associate { it.code to it.name }
        fun regionName(code: String): String = NAMES[code] ?: code
    }
}
