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
import kotlinx.coroutines.flow.first
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
class CoreEngine(
    private val fallback: ZephyrEngine,
    dataDir: String? = null,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    /** Real subscription profiles; null keeps subscriptions on [fallback] (screenshots, tests). */
    val profiles: ProfileStore? = null,
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
    private fun realSubs(): Boolean = profiles != null && (isNative || profiles.subscriptions.value.isNotEmpty())

    override fun subscriptions(): kotlinx.coroutines.flow.Flow<List<Subscription>> =
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

    // ── Nodes ──────────────────────────────────────────────────────────────────────────────────────
    override suspend fun nodeIndex(): NodeIndex {
        val c = nodes() ?: return fallback.nodeIndex()
        val tested = fallback.nodeIndex().testedCount
        return withContext(io) { wrap { c.nodeIndex() }.let { NodeIndex(it.total.toLong(), it.sections.map(::section), tested) } }
    }

    override suspend fun queryNodes(query: String): NodeQueryResult {
        val c = nodes() ?: return fallback.queryNodes(query)
        return withContext(io) {
            wrap { c.queryNodes(query) }.let {
                NodeQueryResult(it.query, it.total.toLong(), it.sections.map(::section), it.highlights, it.tookMicros.toLong(), it.token.toLong())
            }
        }
    }

    override suspend fun nodeRows(token: Long, offset: Long, limit: Int): NodePage {
        val c = nodes() ?: return fallback.nodeRows(token, offset, limit)
        return withContext(io) {
            wrap { c.nodeRows(token.toULong(), offset.toULong(), limit.toUInt()) }.let { p ->
                NodePage(p.rows.map(::row), p.offset.toLong(), p.total.toLong())
            }
        }
    }

    // ── Rules ──────────────────────────────────────────────────────────────────────────────────────
    override suspend fun ruleStats(): RuleStats {
        val c = rules() ?: return fallback.ruleStats()
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
