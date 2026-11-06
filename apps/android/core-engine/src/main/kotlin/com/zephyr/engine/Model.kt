package com.zephyr.engine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/*
 * Kotlin mirror of contract/zephyr-engine.md v0.
 * Units: time = epoch millis, rates = bytes/s, traffic = bytes, latency = ms (null = untested, -1 = timeout).
 * Serial names follow the contract's snake_case.
 */

typealias NodeId = Long

const val LATENCY_TIMEOUT: Int = -1

// ── 1. Connection ───────────────────────────────────────────────────────────

@Serializable
enum class ConnectionStatus {
    @SerialName("disconnected") DISCONNECTED,
    @SerialName("connecting") CONNECTING,
    @SerialName("connected") CONNECTED,
    @SerialName("disconnecting") DISCONNECTING,
    @SerialName("failed") FAILED;

    val isActive: Boolean get() = this == CONNECTED || this == CONNECTING
}

@Serializable
enum class ProxyMode {
    @SerialName("rule") RULE,
    @SerialName("global") GLOBAL,
    @SerialName("direct") DIRECT,
}

@Serializable
enum class NetworkKind {
    @SerialName("wifi") WIFI,
    @SerialName("cellular") CELLULAR,
    @SerialName("ethernet") ETHERNET,
    @SerialName("other") OTHER,
}

@Serializable
data class NetworkInfo(val kind: NetworkKind, val name: String? = null, val trusted: Boolean = false)

@Serializable
data class ConnectionState(
    val status: ConnectionStatus = ConnectionStatus.DISCONNECTED,
    val mode: ProxyMode = ProxyMode.RULE,
    val since: Long? = null,
    val globalNodeId: NodeId? = null,
    val network: NetworkInfo? = null,
    val error: ZephyrError? = null,
)

// ── 2. Traffic ──────────────────────────────────────────────────────────────

@Serializable
data class TrafficSample(val at: Long, val upBps: Long, val downBps: Long)

@Serializable
data class UsageSummary(
    val todayBytes: Long,
    val regionsToday: Int,
    val onlineMillisToday: Long,
    val fastestLatencyMs: Int?,
    val hourly: List<Long>,
)

// ── 3. Scenes ───────────────────────────────────────────────────────────────

@Serializable
enum class SceneKind {
    @SerialName("ai") AI,
    @SerialName("video") VIDEO,
    @SerialName("other") OTHER,
    @SerialName("custom") CUSTOM,
}

@Serializable
enum class SceneSource {
    @SerialName("auto") AUTO,
    @SerialName("manual") MANUAL,
    @SerialName("subscription_group") SUBSCRIPTION_GROUP,
}

@Serializable
data class SceneException(val app: String, val node: NodeSummary)

@Serializable
data class Scene(
    val id: String,
    val kind: SceneKind,
    val name: String,
    val available: Int,
    val selected: NodeSummary,
    val exitIp: String? = null,
    val source: SceneSource = SceneSource.AUTO,
    val testedAt: Long? = null,
    val note: String? = null,
    val exceptions: List<SceneException> = emptyList(),
)

@Serializable
data class ExitChange(
    val sceneId: String?,
    val fromRegion: String,
    val fromIp: String?,
    val toRegion: String,
    val toIp: String?,
    val affectedApps: List<String> = emptyList(),
    val unchangedApps: List<String> = emptyList(),
)

// ── 4. Policy groups ────────────────────────────────────────────────────────

@Serializable
enum class GroupType {
    @SerialName("select") SELECT,
    @SerialName("url_test") URL_TEST,
    @SerialName("fallback") FALLBACK,
    @SerialName("load_balance") LOAD_BALANCE,
    @SerialName("relay") RELAY,
}

@Serializable
data class PolicyGroup(
    val name: String,
    val type: GroupType,
    val selected: String?,
    val memberCount: Int,
    val testedAt: Long? = null,
)

// ── 5. Node library ─────────────────────────────────────────────────────────

@Serializable
data class NodeSummary(
    val id: NodeId,
    val name: String,
    val region: String,
    val city: String? = null,
    val carrier: String? = null,
    val tag: String? = null,
    val protocol: String,
    val multiplier: Float? = null,
    val latencyMs: Int? = null,
)

@Serializable
data class RegionSection(val region: String, val name: String, val count: Long, val rowOffset: Long)

@Serializable
data class NodeIndex(val total: Long, val sections: List<RegionSection>, val testedCount: Long)

@Serializable
data class NodeQueryResult(
    val query: String,
    val total: Long,
    val sections: List<RegionSection>,
    val highlights: List<String>,
    val tookMicros: Long,
    val token: Long,
) {
    /** Virtual list row count: every section contributes one header row. */
    val rowCount: Long get() = total + sections.size
}

@Serializable
data class NodePage(val rows: List<NodeSummary>, val offset: Long, val total: Long)

@Serializable
data class LatencyUpdate(val id: NodeId, val latencyMs: Int, val at: Long)

@Serializable
data class NodeDetail(
    val summary: NodeSummary,
    val server: String,
    val port: Int,
    val subscription: String,
    val extra: Map<String, String> = emptyMap(),
)

// ── 6. Rules ────────────────────────────────────────────────────────────────

@Serializable
enum class LayerKind {
    @SerialName("override") OVERRIDE,
    @SerialName("subscription") SUBSCRIPTION,
    @SerialName("domain") DOMAIN,
    @SerialName("ip") IP,
}

@Serializable
data class RuleLayer(
    val index: Int,
    val kind: LayerKind,
    val name: String,
    val count: Long,
    val note: String,
    val updatedAt: Long? = null,
)

@Serializable
data class RuleStats(val total: Long, val layers: List<RuleLayer>, val compiled: Boolean, val diskBytes: Long)

@Serializable
data class RuleTrace(
    val input: String,
    val isIp: Boolean,
    val layerIndex: Int?,
    val rule: String,
    val ruleNo: Long?,
    val policy: String,
    val scene: Scene? = null,
    val exitIp: String? = null,
    val tookMicros: Long,
)

// ── 7. Subscriptions ────────────────────────────────────────────────────────

@Serializable
data class SubscriptionDiff(
    val addedNodes: Long,
    val removedNodes: Long,
    val ruleChanges: Long,
    val overridesKept: Boolean,
    val scenesRetested: Boolean,
)

@Serializable
data class Subscription(
    val id: String,
    val name: String,
    val url: String? = null,
    val nodeCount: Long,
    val usedBytes: Long? = null,
    val totalBytes: Long? = null,
    val remainingBytes: Long? = null,
    val expiresAt: Long? = null,
    val updatedAt: Long? = null,
    val autoUpdateHours: Int = 12,
    val lastDiff: SubscriptionDiff? = null,
)

@Serializable
data class SubscriptionsSummary(val count: Int, val totalNodes: Long)

@Serializable
enum class ImportSource {
    @SerialName("url") URL,
    @SerialName("clipboard") CLIPBOARD,
    @SerialName("qr") QR,
    @SerialName("file") FILE,
}

// ── 8. Connections, logs, settings ──────────────────────────────────────────

@Serializable
data class ConnectionInfo(
    val id: String,
    val host: String,
    val app: String? = null,
    val scene: String? = null,
    val node: String,
    val upBytes: Long,
    val downBytes: Long,
    val startedAt: Long,
)

@Serializable
enum class LogLevel {
    @SerialName("debug") DEBUG,
    @SerialName("info") INFO,
    @SerialName("warning") WARNING,
    @SerialName("error") ERROR,
}

@Serializable
data class LogLine(val at: Long, val level: LogLevel, val message: String)

@Serializable
enum class Accent {
    @SerialName("blue") BLUE,
    @SerialName("green") GREEN,
    @SerialName("orange") ORANGE,
    @SerialName("pink") PINK,
}

@Serializable
enum class Appearance {
    @SerialName("system") SYSTEM,
    @SerialName("dark") DARK,
    @SerialName("light") LIGHT,
}

@Serializable
data class DnsSettings(
    val fakeIp: Boolean = true,
    val nameservers: List<String> = listOf("https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"),
    val fallback: List<String> = listOf("https://1.1.1.1/dns-query"),
    val ipv6: Boolean = false,
)

/** contract §13. */
@Serializable
enum class TunStack { @SerialName("system") SYSTEM, @SerialName("gvisor") GVISOR, @SerialName("mixed") MIXED }

@Serializable
data class TunSettings(
    val stack: TunStack = TunStack.GVISOR,
    val mtu: Int = 9000,
    val ipv6: Boolean = false,
    val strictRoute: Boolean = true,
    /** Android-only extension (per-app VPN exclusion); not in the shared contract. */
    val excludedApps: List<String> = emptyList(),
)

@Serializable
data class Settings(
    val onDemand: Boolean = false,
    val trustedWifi: List<String> = listOf("家"),
    val disconnectOnTrusted: Boolean = true,
    val localProxyPort: Int = 7890,
    val localProxyAuth: Boolean = true,
    val localProxyEnabled: Boolean = false,
    val testOnWifiOnly: Boolean = true,
    val latencyTtlHours: Int = 24,
    val autoUpdateHours: Int = 12,
    val updateOnWifiOnly: Boolean = true,
    val showChangesBeforeUpdate: Boolean = true,
    val dns: DnsSettings = DnsSettings(),
    val tun: TunSettings = TunSettings(),
    val accent: Accent = Accent.BLUE,
    val appearance: Appearance = Appearance.SYSTEM,
    val shareAnonymousPattern: Boolean = true,
    val shareDiagnostics: Boolean = false,
)

@Serializable
data class StorageInfo(val nodesBytes: Long, val rulesBytes: Long, val freeBytes: Long)

// ── 9. Command search ───────────────────────────────────────────────────────

@Serializable
enum class CommandKind {
    @SerialName("switch_node") SWITCH_NODE,
    @SerialName("switch_mode") SWITCH_MODE,
    @SerialName("open_node_query") OPEN_NODE_QUERY,
    @SerialName("test_rule") TEST_RULE,
    @SerialName("open_page") OPEN_PAGE,
    @SerialName("toggle_connection") TOGGLE_CONNECTION,
}

@Serializable
data class CommandSuggestion(
    val kind: CommandKind,
    val title: String,
    val subtitle: String? = null,
    val payload: String,
)


// ── 13. v0.1: connection trace (prototype trace sheet) ─────────────────────────
@Serializable
enum class TraceTarget { @SerialName("unchanged") UNCHANGED, @SerialName("direct") DIRECT, @SerialName("scene") SCENE }

@Serializable
data class TraceOverride(val target: TraceTarget, val sceneId: String? = null, val persistent: Boolean)

@Serializable
data class ConnectionTrace(
    val host: String,
    val lastSeenAt: Long,
    val connections: Int,
    val totalBytes: Long,
    val rule: String,
    val ruleSource: String? = null,
    val scene: String? = null,
    val sceneSource: String? = null,
    val node: NodeSummary? = null,
    val via: String? = null,
    val exitIp: String? = null,
    val exitRegion: String? = null,
    val exitStableDays: Int? = null,
    val override: TraceOverride? = null,
)
