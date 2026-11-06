package com.zephyr.engine.core

import com.zephyr.core.mobile.MobileCore
import com.zephyr.core.mobile.MobileException
import com.zephyr.core.mobile.SubscriptionSource
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
    dataDir: String? = null,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    /** Real subscription profiles; null keeps subscriptions on [fallback] (screenshots, tests). */
    val profiles: ProfileStore? = null,
    /**
     * Whether [fallback]'s synthetic catalogue may stand in for an empty native store. True for debug,
     * screenshots and tests; false in release, where an empty store means "no subscription yet" and the
     * UI shows its empty state instead of fake nodes.
     */
    private val mockData: Boolean = true,
    /** mihomo's REST controller while the embedded core runs, else null (VPN off, tests, screenshots). */
    private val live: () -> MihomoRest? = { null },
    private val tick: Long = 1_000,
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

    // ── Subscriptions (real profiles once the user imports one) ───────────────────────────────────
    private fun realSubs(): Boolean = profiles != null && (!mockData || isNative || profiles.subscriptions.value.isNotEmpty())

    override fun subscriptions(): Flow<List<Subscription>> =
        if (realSubs()) profiles!!.subscriptions else fallback.subscriptions()

    override suspend fun subscriptionsSummary(): SubscriptionsSummary =
        if (realSubs()) profiles!!.subscriptions.value.let { l -> SubscriptionsSummary(l.size, l.sumOf { it.nodeCount }) }
        else fallback.subscriptionsSummary()

    override suspend fun importSubscription(source: ImportSource, payload: String): Subscription {
        val store = profiles ?: return fallback.importSubscription(source, payload)
        if (!isNative && source == ImportSource.QR) return fallback.importSubscription(source, payload)
        val isUrl = payload.trim().let { it.startsWith("http://") || it.startsWith("https://") }
        if (source == ImportSource.URL && !isUrl) throw ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "not a subscription link")
        return withContext(io) {
            store.import(payload, isUrl) { all ->
                val c = core
                if (c == null) all.sumOf { ProfileStore.countProxies(it.second) }
                else wrap { c.rebuildNodes(all.map { SubscriptionSource(it.first.toUShort(), it.second) }).total.toLong() }.also { nodesReady = null }
            }
        }
    }

    override suspend fun deleteSubscription(id: String) {
        if (!realSubs()) return fallback.deleteSubscription(id)
        withContext(io) {
            profiles!!.delete(id)
            core?.let { c -> wrap { c.rebuildNodes(profiles.sources().map { SubscriptionSource(it.first.toUShort(), it.second) }) }; nodesReady = null }
        }
    }

    // ── Live mihomo (policy groups, connections, mode, delay) ───────────────────────────────────────
    private val names = java.util.concurrent.ConcurrentHashMap<Long, String>()
    private val liveLatency = kotlinx.coroutines.flow.MutableSharedFlow<List<LatencyUpdate>>(extraBufferCapacity = 8)
    @Volatile private var proxyCache: Map<String, MihomoRest.Proxy> = emptyMap()

    /** Emits whether the live controller is reachable; re-checked every few ticks. */
    private val liveFlag: Flow<Boolean> = flow { while (true) { emit(live() != null); delay(tick * 2) } }.distinctUntilChanged()

    /** [real] while mihomo runs, otherwise [mock] (debug) or [empty] (release). */
    private fun <T> switching(real: (MihomoRest) -> Flow<T>, mock: () -> Flow<T>, empty: T): Flow<T> =
        liveFlag.flatMapLatest { on -> live()?.takeIf { on }?.let(real) ?: if (mockData) mock() else flowOf(empty) }

    private fun <T> polling(r: MihomoRest, every: Long, read: (MihomoRest) -> T): Flow<T> = flow {
        while (true) { runCatching { read(r) }.onSuccess { emit(it) }; delay(every) }
    }.flowOn(io)

    private fun proxies(r: MihomoRest): Map<String, MihomoRest.Proxy> = r.proxies().also { proxyCache = it }

    private fun summary(p: MihomoRest.Proxy?, name: String): NodeSummary {
        val id = MihomoRest.idOf(name).also { names[it] = name }
        val region = MihomoRest.regionOf(name)
        return NodeSummary(id = id, name = name, region = region, protocol = p?.type?.uppercase() ?: "", latencyMs = p?.lastDelay?.takeIf { it > 0 })
    }

    private fun groups(all: Map<String, MihomoRest.Proxy>): List<PolicyGroup> = all.values
        .filter { it.type in MihomoRest.GROUP_TYPES && it.name != "GLOBAL" }
        .map { g ->
            PolicyGroup(
                name = g.name,
                type = when (g.type) { "URLTest" -> GroupType.URL_TEST; "Fallback" -> GroupType.FALLBACK; "LoadBalance" -> GroupType.LOAD_BALANCE; "Relay" -> GroupType.RELAY; else -> GroupType.SELECT },
                selected = g.now, memberCount = g.all.size, testedAt = g.all.mapNotNull { all[it]?.lastTestAt }.maxOrNull(),
            )
        }

    // Scenes while live: the profile's selectable groups in config order (GLOBAL.all), kind by name.
    // Interim until core injects Zephyr's own scene groups into active.yaml (asked A, Issue #1).
    private fun leaf(all: Map<String, MihomoRest.Proxy>, name: String): String {
        var cur = name; var hops = 0
        while (hops++ < 8) { val p = all[cur] ?: break; if (p.type !in MihomoRest.GROUP_TYPES) break; cur = p.now ?: break }
        return cur
    }

    private fun liveScenes(all: Map<String, MihomoRest.Proxy>): List<Scene> {
        val order = all["GLOBAL"]?.all ?: all.keys.sorted()
        return order.mapNotNull { all[it] }
            .filter { it.type in MihomoRest.GROUP_TYPES && it.name != "GLOBAL" && it.all.any { m -> !MihomoRest.isBuiltin(m) } }
            .map { g ->
                val leafName = leaf(all, g.name)
                Scene(
                    id = g.name, kind = sceneKind(g.name), name = g.name,
                    available = g.all.count { !MihomoRest.isBuiltin(it) },
                    selected = if (leafName == "DIRECT") NodeSummary(MihomoRest.idOf("DIRECT"), "直连", "CN", protocol = "DIRECT") else summary(all[leafName], leafName),
                    source = if (g.type == "Selector") SceneSource.SUBSCRIPTION_GROUP else SceneSource.AUTO,
                    testedAt = g.all.mapNotNull { all[it]?.lastTestAt }.maxOrNull(),
                )
            }
    }

    override fun scenes(): Flow<List<Scene>> =
        switching({ r -> polling(r, tick * 3) { liveScenes(proxies(it)) }.distinctUntilChanged() }, { fallback.scenes() }, emptyList())

    override suspend fun sceneCandidates(sceneId: String, region: String?): List<NodeSummary> {
        val r = live() ?: return fallback.sceneCandidates(sceneId, region)
        val all = withContext(io) { proxies(r) }
        val g = all[sceneId] ?: throw ZephyrException(ErrorCode.SCENE_NOT_FOUND, sceneId)
        return g.all.filterNot(MihomoRest::isBuiltin).map { summary(all[it], it) }
            .filter { region == null || it.region == region }
            .sortedWith(compareBy(nullsLast()) { it.latencyMs }).take(50)
    }

    override suspend fun previewSceneChange(sceneId: String, nodeId: NodeId): ExitChange {
        val r = live() ?: return fallback.previewSceneChange(sceneId, nodeId)
        val all = withContext(io) { proxies(r) }
        all[sceneId] ?: throw ZephyrException(ErrorCode.SCENE_NOT_FOUND, sceneId)
        val to = names[nodeId] ?: throw ZephyrException(ErrorCode.NODE_NOT_FOUND, "$nodeId")
        return ExitChange(sceneId, MihomoRest.regionOf(leaf(all, sceneId)), null, MihomoRest.regionOf(to), null)
    }

    override suspend fun applySceneChange(sceneId: String, nodeId: NodeId) {
        if (live() == null) return fallback.applySceneChange(sceneId, nodeId)
        selectInGroup(sceneId, nodeId)
    }

    override suspend fun retestScene(sceneId: String): Scene {
        val r = live() ?: return fallback.retestScene(sceneId)
        withContext(io) { liveCall { r.groupDelay(sceneId) } }
        return liveScenes(withContext(io) { proxies(r) }).firstOrNull { it.id == sceneId } ?: throw ZephyrException(ErrorCode.SCENE_NOT_FOUND, sceneId)
    }

    override fun policyGroups(): Flow<List<PolicyGroup>> =
        switching({ r -> polling(r, tick * 3) { groups(proxies(it)) }.distinctUntilChanged() }, { fallback.policyGroups() }, emptyList())

    override suspend fun groupMembers(group: String, offset: Int, limit: Int): NodePage {
        val r = live() ?: return fallback.groupMembers(group, offset, limit)
        val all = withContext(io) { proxies(r) }
        val g = all[group]?.takeIf { it.type in MihomoRest.GROUP_TYPES } ?: throw ZephyrException(ErrorCode.GROUP_NOT_FOUND, group)
        val rows = g.all.drop(offset).take(limit.coerceIn(0, 500)).map { summary(all[it], it) }
        return NodePage(rows, offset.toLong(), g.all.size.toLong())
    }

    override suspend fun selectInGroup(group: String, nodeId: NodeId) {
        val r = live() ?: return fallback.selectInGroup(group, nodeId)
        val name = names[nodeId] ?: throw ZephyrException(ErrorCode.NODE_NOT_FOUND, nodeId.toString())
        withContext(io) { liveCall { r.select(group, name) } }
    }

    override suspend fun testGroup(group: String) {
        val r = live() ?: return fallback.testGroup(group)
        val delays = withContext(io) { liveCall { r.groupDelay(group) } }
        val members = proxyCache[group]?.all ?: delays.keys.toList()
        val now = System.currentTimeMillis()
        liveLatency.tryEmit(members.map { LatencyUpdate(MihomoRest.idOf(it).also { id -> names[id] = it }, delays[it] ?: -1, now) })
    }

    override fun latencyUpdates(): Flow<List<LatencyUpdate>> = merge(fallback.latencyUpdates(), liveLatency)

    override suspend fun setMode(mode: ProxyMode) {
        live()?.let { r -> withContext(io) { liveCall { r.setMode(mode.name.lowercase()) } } }
        fallback.setMode(mode)
    }

    private fun connInfo(c: MihomoRest.Conn0): ConnectionInfo {
        val direct = c.chains.isEmpty() || c.chains.first() == "DIRECT"
        return ConnectionInfo(
            id = c.id, host = c.host, app = c.process, scene = if (direct) null else c.chains.last(),
            node = if (direct) "直连" else c.chains.first(), upBytes = c.up, downBytes = c.down, startedAt = c.startMillis,
        )
    }

    override fun traffic(): Flow<TrafficSample> = switching({ _ ->
        flow { while (true) { Mihomo.traffic()?.let { emit(TrafficSample(System.currentTimeMillis(), it.upBps, it.downBps)) }; delay(tick) } }.flowOn(io)
    }, { fallback.traffic() }, TrafficSample(0, 0, 0))

    override fun activeConnections(): Flow<List<ConnectionInfo>> =
        switching({ r -> polling(r, tick) { it.connections().map(::connInfo) } }, { fallback.activeConnections() }, emptyList())

    override suspend fun closeConnection(id: String) { live()?.let { r -> withContext(io) { liveCall { r.closeConnection(id) } } } ?: fallback.closeConnection(id) }
    override suspend fun closeAll() { live()?.let { r -> withContext(io) { liveCall { r.closeAll() } } } ?: fallback.closeAll() }

    override fun recentHosts(limit: Int): Flow<List<ConnectionInfo>> = switching({ r ->
        polling(r, tick) { rr ->
            rr.connections().groupBy { it.host }.values
                .map { cs -> val last = cs.maxBy { it.startMillis }; connInfo(last).copy(upBytes = cs.sumOf { it.up }, downBytes = cs.sumOf { it.down }) }
                .sortedByDescending { it.startedAt }.take(limit.coerceIn(0, 50))
        }
    }, { fallback.recentHosts(limit) }, emptyList())

    override suspend fun connectionTrace(host: String): ConnectionTrace {
        val r = live() ?: return fallback.connectionTrace(host)
        val cs = withContext(io) { liveCall { r.connections() } }.filter { it.host == host }
        if (cs.isEmpty()) throw ZephyrException(ErrorCode.NODE_NOT_FOUND, host)
        val last = cs.maxBy { it.startMillis }
        val direct = last.chains.isEmpty() || last.chains.first() == "DIRECT"
        val nodeName = last.chains.firstOrNull()
        return ConnectionTrace(
            host = host, lastSeenAt = last.startMillis, connections = cs.size, totalBytes = cs.sumOf { it.up + it.down },
            rule = MihomoRest.ruleText(last.rule, last.rulePayload),
            scene = if (direct) null else last.chains.last(),
            node = if (direct || nodeName == null) null else summary(proxyCache[nodeName], nodeName),
            via = last.chains.drop(1).dropLast(1).takeIf { it.isNotEmpty() }?.joinToString(" · "),
        )
    }

    override suspend fun overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Boolean) {
        if (live() == null) return fallback.overrideHost(host, target, sceneId, persistent)
        // Needs the Zephyr override rule layer in the running config (contract §13); not wired to mihomo yet.
        throw ZephyrException(ErrorCode.INTERNAL, "override not available yet")
    }

    private fun sceneKind(name: String): SceneKind {
        val n = name.lowercase()
        return when {
            listOf("ai", "openai", "chatgpt", "gpt", "claude", "gemini", "copilot").any { k -> Regex("(^|[^a-z])$k([^a-z]|$)").containsMatchIn(n) } -> SceneKind.AI
            listOf("视频", "流媒体", "媒体", "netflix", "youtube", "disney", "stream", "media", "video").any { n.contains(it) } -> SceneKind.VIDEO
            listOf("其他", "其它", "漏网", "final", "other", "fallback").any { n.contains(it) } -> SceneKind.OTHER
            else -> SceneKind.CUSTOM
        }
    }

    private inline fun <T> liveCall(block: () -> T): T = try { block() } catch (e: MihomoRest.HttpException) {
        throw ZephyrException(if (e.status == 404) ErrorCode.GROUP_NOT_FOUND else ErrorCode.INTERNAL, e.message ?: "")
    } catch (e: java.io.IOException) {
        throw ZephyrException(ErrorCode.NOT_RUNNING, e.message ?: "controller unreachable")
    }

    // ── Nodes ──────────────────────────────────────────────────────────────────────────────────────
    override suspend fun nodeIndex(): NodeIndex {
        val c = nodes() ?: return if (mockData) fallback.nodeIndex() else NodeIndex(0, emptyList(), 0)
        val tested = fallback.nodeIndex().testedCount
        return withContext(io) { wrap { c.nodeIndex() }.let { NodeIndex(it.total.toLong(), it.sections.map(::section), tested) } }
    }

    override suspend fun queryNodes(query: String): NodeQueryResult {
        val c = nodes() ?: return if (mockData) fallback.queryNodes(query) else NodeQueryResult(query, 0, emptyList(), emptyList(), 0, 0)
        return withContext(io) {
            wrap { c.queryNodes(query) }.let {
                NodeQueryResult(it.query, it.total.toLong(), it.sections.map(::section), it.highlights, it.tookMicros.toLong(), it.token.toLong())
            }
        }
    }

    override suspend fun nodeRows(token: Long, offset: Long, limit: Int): NodePage {
        val c = nodes() ?: return if (mockData) fallback.nodeRows(token, offset, limit) else NodePage(emptyList(), offset, 0)
        return withContext(io) {
            wrap { c.nodeRows(token.toULong(), offset.toULong(), limit.toUInt()) }.let { p ->
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
        val code = when (e) {
            is MobileException.NotFound -> ErrorCode.NODE_NOT_FOUND
            is MobileException.Invalid -> ErrorCode.RULE_INPUT_INVALID
            else -> ErrorCode.INTERNAL
        }
        throw ZephyrException(ZephyrError(code, e.message ?: e.javaClass.simpleName))
    }

    companion object {
        private val NAMES: Map<String, String> = MockCatalog.REGIONS.associate { it.code to it.name }
        fun regionName(code: String): String = NAMES[code] ?: code
    }
}
