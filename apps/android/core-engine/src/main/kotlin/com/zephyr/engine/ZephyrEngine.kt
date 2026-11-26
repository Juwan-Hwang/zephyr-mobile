package com.zephyr.engine

import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The single seam between UI and core (contract/zephyr-engine.md v0).
 *
 * - Every list is count + index + paging; nothing returns the full node or rule set.
 * - All calls are main-safe: implementations move work off the main thread themselves.
 * - Hot streams ([connectionState], [scenes], [settings] …) replay the current value on collect.
 */
interface ZephyrEngine {
    // 1. Connection
    fun connectionState(): Flow<ConnectionState>
    suspend fun connect()
    suspend fun disconnect()
    suspend fun setMode(mode: ProxyMode)
    suspend fun setGlobalNode(id: NodeId): ExitChange

    // 2. Traffic
    fun traffic(): Flow<TrafficSample>
    suspend fun recentTraffic(seconds: Int): List<TrafficSample>
    suspend fun usageToday(): UsageSummary

    // 3. Scenes
    fun scenes(): Flow<List<Scene>>
    suspend fun sceneCandidates(sceneId: String, region: String?): List<NodeSummary>
    suspend fun previewSceneChange(sceneId: String, nodeId: NodeId): ExitChange
    suspend fun applySceneChange(sceneId: String, nodeId: NodeId)
    suspend fun retestScene(sceneId: String): Scene
    /** Progress of the node scan a [retestScene] runs (contract §15.d, platform-local); null = not scanning. */
    fun scanProgress(): Flow<ScanProgress?> = kotlinx.coroutines.flow.flowOf(null)
    /**
     * Scene sheet funnel (contract §15.c): 全部 → 已测速 → 可连通 → 延迟低于 [thresholdMs]. [maxAgeMs] is the
     * latency freshness window (设置 › 结果保留, §15.e). Null when the engine cannot count (no core, no data).
     */
    suspend fun nodeFunnel(maxAgeMs: Long, thresholdMs: Int): NodeFunnel? = null
    /**
     * Home scene-row mini funnel (contract v0.7 §19.a `sceneFunnel`): same fields as [nodeFunnel] but scoped to the
     * scene's candidate range (current node's region + §15.h node filter, not capped at 50). A scene with no node yet
     * returns all zeros; null when the engine cannot count (no core, unknown scene) — the row then keeps its text.
     */
    suspend fun sceneFunnel(sceneId: String, maxAgeMs: Long, thresholdMs: Int): NodeFunnel? = null
    /**
     * Pins one app of a scene to a node ("Gemini 走日本" → Gemini：东京 03; contract §14 setSceneException).
     * `nodeId = null` removes the pin. Never called by automation: only on an explicit, confirmed user action.
     */
    /**
     * Scene source (contract §14.z ②): AUTO ("Zephyr 优选") moves to the best tested node now; returns the new exit
     * when it changed. Callers must confirm first for AI scenes (exit IP rule, §14.y).
     */
    suspend fun setSceneSource(sceneId: String, source: SceneSource): NodeSummary? =
        throw ZephyrException(ErrorCode.INTERNAL, "setSceneSource unsupported")

    /** Exit change for global mode before it happens (prototype `gcf` IP line). */
    suspend fun previewGlobalChange(nodeId: NodeId): ExitChange = setGlobalNodePreviewUnsupported()

    suspend fun setSceneException(sceneId: String, appId: String, nodeId: NodeId?): Unit =
        throw ZephyrException(ErrorCode.INTERNAL, "setSceneException unsupported")

    /** §15.h: what filtering this scene's candidates would keep; call before [setSceneNodeFilter]. */
    suspend fun previewSceneNodeFilter(sceneId: String, filter: SceneNodeFilter): NodeFilterPreview =
        throw ZephyrException(ErrorCode.INTERNAL, "previewSceneNodeFilter unsupported")

    /**
     * §15.h: persists the filter (null clears). Never moves the current node; the caller applies the preview's
     * `suggested` with [applySceneChange] after the user confirmed the exit-IP line.
     */
    suspend fun setSceneNodeFilter(sceneId: String, filter: SceneNodeFilter?): Unit =
        throw ZephyrException(ErrorCode.INTERNAL, "setSceneNodeFilter unsupported")

    // 4. Policy groups
    fun policyGroups(): Flow<List<PolicyGroup>>
    suspend fun groupMembers(group: String, offset: Int, limit: Int): NodePage
    suspend fun selectInGroup(group: String, nodeId: NodeId)
    suspend fun testGroup(group: String)

    // 5. Node library
    suspend fun nodeIndex(): NodeIndex
    suspend fun queryNodes(query: String): NodeQueryResult
    suspend fun nodeRows(token: Long, offset: Long, limit: Int): NodePage
    suspend fun node(id: NodeId): NodeDetail
    suspend fun testLatency(ids: List<NodeId>)
    fun latencyUpdates(): Flow<List<LatencyUpdate>>

    // 6. Rules
    suspend fun ruleStats(): RuleStats
    suspend fun testRule(input: String): RuleTrace

    // 7. Subscriptions
    fun subscriptions(): Flow<List<Subscription>>
    suspend fun subscriptionsSummary(): SubscriptionsSummary
    suspend fun importSubscription(source: ImportSource, payload: String): Subscription

    /**
     * Contract §15 `parseImportPayload`: pure parsing, no network. Throws [ImportPayloadException].
     * The real engine asks core-mobile; the default is the Kotlin twin checked against the same fixture.
     */
    fun parseImportPayload(payload: String): ImportPayload = ImportPayloads.parse(payload)

    /**
     * Imports one item of a parsed payload (§15 platform flow: parse → confirm → fetch and import each), keeping the
     * payload's name and auto-update interval. The default only knows the link.
     */
    suspend fun importItem(source: ImportSource, item: ImportItem): Subscription = importSubscription(source, item.url)
    suspend fun previewUpdate(id: String): SubscriptionDiff
    suspend fun updateSubscription(id: String): SubscriptionDiff
    suspend fun updateAll(): List<SubscriptionDiff>
    suspend fun deleteSubscription(id: String)
    /**
     * Contract §22.a: makes [id] the active subscription — moved to the front of the list and saved, the others keep
     * their relative order — and returns the new list. While the tunnel runs the config is rebuilt from the new first
     * subscription and reloaded (only when the order changed). Unknown id → `subscription_not_found`.
     */
    suspend fun setActiveSubscription(id: String): List<Subscription>
    /**
     * Contract §22.b (U27 revised): text for the collapsed 错误详情 — whitespace folded, http(s) URLs redacted,
     * cut to 240 characters. The native engine calls core `redactDiagnostic`; this default ([Diagnostics.fallbackRedact])
     * is only for engines without the core (mock, screenshots, core not loaded).
     */
    fun redactDiagnostic(text: String): String = Diagnostics.fallbackRedact(text)

    // 8. Connections, logs, settings
    fun activeConnections(): Flow<List<ConnectionInfo>>
    suspend fun closeConnection(id: String)
    suspend fun closeAll()

    // v0.1 (§13): per-host aggregation and trace
    fun recentHosts(limit: Int): Flow<List<ConnectionInfo>>
    suspend fun connectionTrace(host: String): ConnectionTrace
    suspend fun overrideHost(host: String, target: TraceTarget, sceneId: String?, persistent: Boolean)
    fun logs(minLevel: LogLevel): Flow<LogLine>
    /**
     * Contract §16.h: mihomo's own log level, hot (no reload). The log page sets DEBUG while its debug segment is
     * shown and INFO when it leaves; never persisted. No-op while the core is not running (and in the mock).
     */
    suspend fun setLogLevel(level: LogLevel) {}
    fun settings(): Flow<Settings>
    suspend fun updateSettings(patch: Settings)
    suspend fun storage(): StorageInfo

    /**
     * Contract §16.g ① (U9): the local proxy credential `zephyr:<24>`, generated and saved on first use. Platform
     * engine only (not FFI); kept in platform secure storage, never written by the core.
     */
    suspend fun localProxyCredential(): String

    /**
     * A new password (the user suspects a leak). While the tunnel runs with 本地代理 on and 需要密码 on, the core is
     * hot-reloaded; a failed reload puts the old one back and throws (§16.b③).
     */
    suspend fun resetLocalProxyCredential(): String

    // 9. Command search
    suspend fun commandSuggestions(input: String): List<CommandSuggestion>
}

@Serializable
enum class ErrorCode {
    @SerialName("not_running") NOT_RUNNING,
    @SerialName("vpn_permission_denied") VPN_PERMISSION_DENIED,
    @SerialName("network_unavailable") NETWORK_UNAVAILABLE,
    @SerialName("subscription_invalid") SUBSCRIPTION_INVALID,
    @SerialName("subscription_fetch_failed") SUBSCRIPTION_FETCH_FAILED,
    @SerialName("node_not_found") NODE_NOT_FOUND,
    @SerialName("scene_not_found") SCENE_NOT_FOUND,
    @SerialName("group_not_found") GROUP_NOT_FOUND,
    @SerialName("rule_input_invalid") RULE_INPUT_INVALID,
    @SerialName("core_crashed") CORE_CRASHED,
    @SerialName("storage_full") STORAGE_FULL,
    @SerialName("cancelled") CANCELLED,
    @SerialName("stale_token") STALE_TOKEN,
    @SerialName("subscription_not_found") SUBSCRIPTION_NOT_FOUND,
    @SerialName("internal") INTERNAL,
}

/** Engine errors carry a code for UI localisation; [message] is for logs only. */
@Serializable
data class ZephyrError(val code: ErrorCode, val message: String = "")

/** Thrown by engine calls; carries the serialisable [error]. */
class ZephyrException(val error: ZephyrError) : Exception("${error.code}: ${error.message}") {
    constructor(code: ErrorCode, message: String = "") : this(ZephyrError(code, message))
    val code: ErrorCode get() = error.code
    init { RecentErrors.record(error.code) }
}

/**
 * Last error codes with their time, for the diagnostics summary a log export may carry (contract §16.c
 * shareDiagnostics: "最近 20 个错误码与时间"). Codes only, never messages. Process-local, not persisted.
 */
object RecentErrors {
    const val CAPACITY = 20
    data class Entry(val at: Long, val code: ErrorCode)
    private val ring = ArrayDeque<Entry>()
    @Volatile var clock: () -> Long = System::currentTimeMillis

    fun record(code: ErrorCode) = synchronized(ring) {
        ring.addLast(Entry(clock(), code))
        while (ring.size > CAPACITY) ring.removeFirst()
    }

    fun snapshot(): List<Entry> = synchronized(ring) { ring.toList() }
    fun clear() = synchronized(ring) { ring.clear() }
}

private fun setGlobalNodePreviewUnsupported(): Nothing = throw ZephyrException(ErrorCode.INTERNAL, "previewGlobalChange unsupported")
