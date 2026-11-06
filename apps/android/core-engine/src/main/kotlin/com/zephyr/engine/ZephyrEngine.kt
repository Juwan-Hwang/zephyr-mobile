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
    suspend fun previewUpdate(id: String): SubscriptionDiff
    suspend fun updateSubscription(id: String): SubscriptionDiff
    suspend fun updateAll(): List<SubscriptionDiff>
    suspend fun deleteSubscription(id: String)

    // 8. Connections, logs, settings
    fun activeConnections(): Flow<List<ConnectionInfo>>
    suspend fun closeConnection(id: String)
    suspend fun closeAll()
    fun logs(minLevel: LogLevel): Flow<LogLine>
    fun settings(): Flow<Settings>
    suspend fun updateSettings(patch: Settings)
    suspend fun storage(): StorageInfo

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
    @SerialName("internal") INTERNAL,
}

/** Engine errors carry a code for UI localisation; [message] is for logs only. */
@Serializable
data class ZephyrError(val code: ErrorCode, val message: String = "")

/** Thrown by engine calls; carries the serialisable [error]. */
class ZephyrException(val error: ZephyrError) : Exception("${error.code}: ${error.message}") {
    constructor(code: ErrorCode, message: String = "") : this(ZephyrError(code, message))
    val code: ErrorCode get() = error.code
}
