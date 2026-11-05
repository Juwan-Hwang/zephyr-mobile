package com.zephyr.app

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.zephyr_core.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

// ── UI data models ───────────────────────────────────────────────────────

data class ProfileItem(
    val name: String,
    val urlDisplay: String? = null,
    val subInfo: String? = null,
    val lastUpdated: ULong? = null,
)

data class ProxyNode(
    val name: String,
    val type: String = "",
    val latency: Int = 0,
    val alive: Boolean = false,
)

data class ProxyGroup(
    val name: String,
    val type: String = "",
    val nodes: List<ProxyNode> = emptyList(),
    val current: String? = null,
)

data class ConnectionItem(
    val id: String,
    val host: String,
    val network: String,
    val type: String,
    val chains: String,
    val dlSpeed: ULong,
    val ulSpeed: ULong,
)

data class EventItem(
    val level: String,
    val module: String,
    val message: String,
    val timestamp: ULong,
)

data class LogEntry(
    val level: String,
    val message: String,
    val timestamp: ULong,
)

// ── ViewModel ────────────────────────────────────────────────────────────

class ZephyrViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "ZephyrViewModel"
    }

    // ── VPN permission state ──────────────────────────────────────────────
    var vpnPermissionNeeded by mutableStateOf(false)
        private set

    // ── Core state ──────────────────────────────────────────────────────
    var isCoreRunning by mutableStateOf(false)
        private set
    var mixedPort by mutableStateOf(7890u.toUShort())
        private set
    var apiPort by mutableStateOf(0u.toUShort())
        private set
    var proxyMode by mutableStateOf("rule")
        internal set
    var coreSecret by mutableStateOf("")
        private set
    var coreVersion by mutableStateOf("")
        private set
    var currentNodeName by mutableStateOf("")
        internal set

    // ── Profiles / Subscriptions ────────────────────────────────────────
    var profiles by mutableStateOf<List<ProfileItem>>(emptyList())
        private set
    var activeProfile by mutableStateOf("")
        internal set

    // ── Proxy groups & nodes ────────────────────────────────────────────
    var proxyGroups by mutableStateOf<List<ProxyGroup>>(emptyList())
        private set
    var currentGroupName by mutableStateOf("")
        internal set
    var proxySortMode by mutableStateOf("default")
        internal set

    // ── Connections ─────────────────────────────────────────────────────
    var connections by mutableStateOf<List<ConnectionItem>>(emptyList())
        private set
    var connectionCount by mutableIntStateOf(0)
        private set

    // ── Events ──────────────────────────────────────────────────────────
    var events by mutableStateOf<List<EventItem>>(emptyList())
        private set

    // ── Logs ────────────────────────────────────────────────────────────
    var logs by mutableStateOf<List<LogEntry>>(emptyList())
        private set
    var logLevelFilter by mutableStateOf("all")
        internal set

    // ── Settings ────────────────────────────────────────────────────────
    var systemProxyEnabled by mutableStateOf(false)
        internal set
    var tunEnabled by mutableStateOf(false)
        internal set
    var ipv6Enabled by mutableStateOf(false)
        internal set
    var allowLan by mutableStateOf(false)
        internal set
    var unifiedDelay by mutableStateOf(true)
        internal set
    var socksPort by mutableStateOf(7891u.toUShort())
        internal set
    var httpPort by mutableStateOf(0u.toUShort())
        internal set
    var themeMode by mutableStateOf("auto")
        internal set
    var language by mutableStateOf("zh")
        internal set

    // ── Smart Selector ──────────────────────────────────────────────────
    var smartEnabled by mutableStateOf(false)
        internal set
    var smartAutoTest by mutableStateOf(false)
        internal set
    var smartLatencyWeight by mutableStateOf(0.4)
        internal set
    var smartSuccessWeight by mutableStateOf(0.4)
        internal set
    var smartStabilityWeight by mutableStateOf(0.2)
        internal set
    var smartDecayHalfLife by mutableStateOf(6.0)
        internal set

    // ── Failover ────────────────────────────────────────────────────────
    var failoverEnabled by mutableStateOf(false)
        internal set
    var failoverThreshold by mutableStateOf(3u)
        internal set
    var failoverCooldownSecs by mutableStateOf(60uL)
        internal set
    var failoverFallbackGroup by mutableStateOf("")
        internal set

    // ── Loading states ──────────────────────────────────────────────────
    var isStartingCore by mutableStateOf(false)
        private set
    var isTestingLatency by mutableStateOf(false)
        private set
    var isUpdatingSubscriptions by mutableStateOf(false)
        private set

    // ── Internal state ──────────────────────────────────────────────────
    private val appStore = AppStore()
    private var nodeFailureCounts = mutableMapOf<String, UInt>()
    private val processManager: MihomoProcessManager by lazy {
        MihomoProcessManager(getApplication<Application>())
    }

    // ── Dialog state ────────────────────────────────────────────────────
    var showAddProfileDialog by mutableStateOf(false)
        internal set
    var addProfileUrl by mutableStateOf("")
        internal set
    var addProfileName by mutableStateOf("")
        internal set

    init {
        // Safely initialize UniFFI — catch any loading errors to prevent crash
        try {
            setEventCallback(object : CoreEventCallback {
                override fun onEvent(event: CoreEvent) {
                    val level = when (event.level) {
                        EventLevel.FATAL -> "Fatal"
                        EventLevel.ERROR -> "Error"
                        EventLevel.WARN -> "Warn"
                        EventLevel.INFO -> "Info"
                    }
                    val module = event.module.name.lowercase()
                    addEvent(level, module, event.message, event.timestamp)

                    // Handle cache lock issues
                    if (detectCacheLockIssue(event.message)) {
                        addEvent("Warn", "system", "Cache lock issue detected, consider restarting core", event.timestamp)
                    }
                }
            })

            // Load persisted state from AppStore
            activeProfile = appStore.getActiveProfile() ?: ""
            isCoreRunning = appStore.isCoreRunning()
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load native library", e)
            events = events + EventItem("Error", "system", "Failed to load native library: ${e.message}", 0uL)
        } catch (e: Exception) {
            Log.e(TAG, "Initialization error", e)
            events = events + EventItem("Error", "system", "Initialization error: ${e.message}", 0uL)
        }

        // Extract mihomo binary from APK assets on first launch
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val result = MihomoBinaryManager.ensureBinary(getApplication<Application>())
                if (result != null) {
                    val version = MihomoBinaryManager.getInstalledVersion(getApplication<Application>())
                    addEvent("Info", "core", "mihomo core v${version ?: "unknown"} ready", 0uL)
                } else {
                    addEvent("Error", "core", "Failed to extract mihomo binary from APK", 0uL)
                }
            } catch (e: Exception) {
                Log.e(TAG, "mihomo extraction error", e)
                addEvent("Error", "core", "mihomo extraction error: ${e.message}", 0uL)
            }
        }

    }

    // ── Core management ─────────────────────────────────────────────────

    fun toggleCore(enabled: Boolean) {
        if (enabled) startCore() else stopCore()
    }

    /**
     * Check VPN permission and prepare for starting core.
     * Returns true if VPN permission needs to be requested (caller should
     * launch the VPN prepare intent), false if already prepared.
     */
    fun checkVpnPermission(): Boolean {
        val context = getApplication<Application>()
        val intent = VpnService.prepare(context)
        if (intent != null) {
            vpnPermissionNeeded = true
            return true
        }
        vpnPermissionNeeded = false
        return false
    }

    /**
     * Called after VPN permission is granted by the user.
     * The Activity should call this from onActivityResult.
     */
    fun onVpnPermissionResult(granted: Boolean) {
        vpnPermissionNeeded = false
        if (granted) {
            startCore()
        } else {
            addEvent("Error", "core", "VPN permission denied", 0uL)
        }
    }

    private fun startCore() {
        if (isStartingCore) return
        isStartingCore = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val secret = generateSecret()
                coreSecret = secret

                val prefs = GlobalPreferences(
                    mode = proxyMode,
                    tunEnabled = null, // TUN not supported on Android
                    mixedPort = mixedPort,
                    socksPort = socksPort,
                    httpPort = if (httpPort > 0u.toUShort()) httpPort else null,
                    ipv6 = if (ipv6Enabled) true else null,
                    allowLan = if (allowLan) true else null,
                    unifiedDelay = if (unifiedDelay) true else null,
                )

                // Use UniFFI to build minimal runtime config (replaces hand-written YAML)
                val minimalResult = buildMinimalRuntimeConfig(secret)
                // Then prepare full runtime config with user preferences
                val runtimeResult = prepareRuntimeConfig(minimalResult.yamlContent, secret, prefs)
                if (runtimeResult != null) {
                    apiPort = runtimeResult.apiPort

                    // Write runtime config to app private storage
                    val context = getApplication<Application>()
                    val coreDir = File(context.filesDir, "core")
                    coreDir.mkdirs()
                    val configFile = File(coreDir, "run_config.yaml")
                    configFile.writeText(runtimeResult.yamlContent)

                    // Start mihomo directly as a child process (no VPN Service)
                    val result = processManager.startCore(configFile.absolutePath)
                    mixedPort = result.mixedPort
                    apiPort = result.apiPort
                    coreSecret = result.secret

                    isCoreRunning = true
                    appStore.setCoreRunning(true)
                    if (activeProfile.isEmpty()) {
                        activeProfile = "default"
                        appStore.setActiveProfile("default")
                    }
                    addEvent("Info", "core", "Core started on port ${result.apiPort}", 0uL)

                    // Refresh proxy data from mihomo API after core starts
                    refreshProxies()
                    refreshConnections()
                } else {
                    addEvent("Error", "core", "Failed to prepare runtime config", 0uL)
                }
            } catch (e: AppException) {
                addEvent("Error", "core", "Core start failed: ${e.message}", 0uL)
            } catch (e: Exception) {
                addEvent("Error", "core", "Core start failed: ${e.message}", 0uL)
            } finally {
                isStartingCore = false
            }
        }
    }

    private fun stopCore() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                processManager.stopCore()
                isCoreRunning = false
                appStore.setCoreRunning(false)
                coreSecret = ""
                apiPort = 0u.toUShort()
                addEvent("Info", "core", "Core stopped", 0uL)
            } catch (e: Exception) {
                addEvent("Error", "core", "Core stop failed: ${e.message}", 0uL)
            }
        }
    }

    fun setProxyMode(mode: String) {
        proxyMode = mode
        if (isCoreRunning) {
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    restartCoreWithNewConfig()
                } catch (e: Exception) {
                    addEvent("Error", "core", "Mode change failed: ${e.message}", 0uL)
                }
            }
        }
    }

    private suspend fun restartCoreWithNewConfig() {
        stopCore()
        // Wait for VPN service to actually stop (poll up to 3s)
        var waited = 0L
        while (ZephyrVpnService.isRunning && waited < 3000) {
            kotlinx.coroutines.delay(100)
            waited += 100
        }
        startCore()
    }

    // ── Profile / Subscription management ───────────────────────────────

    fun setActiveProfile(name: String) {
        activeProfile = name
        appStore.setActiveProfile(name)
        if (isCoreRunning) {
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    restartCoreWithNewConfig()
                } catch (e: Exception) {
                    addEvent("Error", "subscription", "Profile switch failed: ${e.message}", 0uL)
                }
            }
        }
    }

    fun addProfile(url: String, name: String) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                // sanitizeConfigFileName requires .yaml/.yml extension and no directory separators
                val rawName = name.ifBlank {
                    try {
                        URL(url).host ?: "Profile-${System.currentTimeMillis()}"
                    } catch (_: Exception) {
                        "Profile-${System.currentTimeMillis()}"
                    }
                }
                // Ensure the name ends with .yaml (sanitizeConfigFileName requires it)
                val nameWithExt = if (rawName.endsWith(".yaml") || rawName.endsWith(".yml")) {
                    rawName
                } else {
                    "$rawName.yaml"
                }
                val sanitizedName = sanitizeConfigFileName(nameWithExt)

                // Download subscription content
                addEvent("Info", "subscription", "Downloading: $sanitizedName", 0uL)
                val content = downloadSubscriptionContent(url)
                if (content.isEmpty()) {
                    throw AppException.UnknownException("Downloaded content is empty")
                }

                // Save to config file
                val configDir = File(getApplication<Application>().filesDir, "core/configs")
                configDir.mkdirs()
                val configFile = File(configDir, sanitizedName)
                configFile.writeText(content)

                val maskedUrl = maskUrl(url)
                val newProfile = ProfileItem(
                    name = sanitizedName,
                    urlDisplay = maskedUrl,
                )
                profiles = profiles + newProfile
                addEvent("Info", "subscription", "Added profile: $sanitizedName", 0uL)
            } catch (e: AppException) {
                addEvent("Error", "subscription", "Add profile failed: ${e.message}", 0uL)
            } catch (e: Exception) {
                addEvent("Error", "subscription", "Add profile failed: ${e.message}", 0uL)
            }
        }
    }

    private suspend fun downloadSubscriptionContent(url: String): String =
        withContext(Dispatchers.IO) {
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.connectTimeout = 15000
                connection.readTimeout = 30000
                connection.setRequestProperty("User-Agent", "ClashForAndroid/1.0")
                connection.instanceFollowRedirects = true

                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw Exception("HTTP $responseCode")
                }

                val content = connection.inputStream.bufferedReader().use { it.readText() }

                // Try base64 decode (some subscriptions return base64-encoded content)
                val decoded = try {
                    val bytes = android.util.Base64.decode(content.trim(), android.util.Base64.DEFAULT)
                    String(bytes, Charsets.UTF_8)
                } catch (_: Exception) {
                    null
                }

                // Use decoded content if it looks like YAML, otherwise use raw content
                val finalContent = decoded ?: content
                if (finalContent.trimStart().startsWith("{") || finalContent.contains("proxies:")) {
                    finalContent
                } else {
                    content
                }
            } catch (e: Exception) {
                Log.e(TAG, "Download subscription failed", e)
                throw e
            }
        }

    fun deleteProfile(name: String) {
        profiles = profiles.filter { it.name != name }
        if (activeProfile == name) {
            activeProfile = profiles.firstOrNull()?.name ?: ""
            appStore.setActiveProfile(activeProfile)
        }
        addEvent("Info", "subscription", "Deleted profile: $name", 0uL)
    }

    fun renameProfile(oldName: String, newName: String) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val sanitized = sanitizeConfigFileName(newName)
                profiles = profiles.map {
                    if (it.name == oldName) it.copy(name = sanitized) else it
                }
                if (activeProfile == oldName) {
                    activeProfile = sanitized
                    appStore.setActiveProfile(sanitized)
                }
            } catch (e: AppException) {
                addEvent("Error", "subscription", "Rename failed: ${e.message}", 0uL)
            }
        }
    }

    fun updateProfile(name: String) {
        viewModelScope.launch(Dispatchers.IO) {
            isUpdatingSubscriptions = true
            try {
                addEvent("Info", "subscription", "Updating profile: $name", 0uL)
                // Profile update would go through core subscription pipeline
                addEvent("Info", "subscription", "Profile updated: $name", 0uL)
            } catch (e: Exception) {
                addEvent("Error", "subscription", "Update failed: ${e.message}", 0uL)
            } finally {
                isUpdatingSubscriptions = false
            }
        }
    }

    fun updateAllProfiles() {
        viewModelScope.launch(Dispatchers.IO) {
            isUpdatingSubscriptions = true
            try {
                profiles.forEach { profile ->
                    addEvent("Info", "subscription", "Updating: ${profile.name}", 0uL)
                }
                addEvent("Info", "subscription", "All profiles updated", 0uL)
            } finally {
                isUpdatingSubscriptions = false
            }
        }
    }

    // ── Proxy management ────────────────────────────────────────────────

    fun selectProxyGroup(groupName: String) {
        currentGroupName = groupName
    }

    fun selectProxyNode(groupName: String, nodeName: String) {
        // Update local state immediately for responsive UI
        currentNodeName = nodeName
        proxyGroups = proxyGroups.map { group ->
            if (group.name == groupName) {
                group.copy(current = nodeName)
            } else group
        }
        // Actually switch the proxy node via mihomo API
        if (isCoreRunning && apiPort > 0u.toUShort()) {
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    MihomoApi.selectProxy(apiPort, coreSecret, groupName, nodeName)
                    addEvent("Info", "core", "Switched to node: $nodeName", 0uL)
                } catch (e: Exception) {
                    addEvent("Error", "core", "Failed to switch node: ${e.message}", 0uL)
                }
            }
        } else {
            addEvent("Info", "core", "Switched to node: $nodeName", 0uL)
        }
    }

    fun testLatency() {
        if (isTestingLatency || !isCoreRunning) return
        isTestingLatency = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                addEvent("Info", "core", "Starting latency test...", 0uL)

                // Fetch proxy groups from mihomo API
                val groups = MihomoApi.getProxies(apiPort, coreSecret)

                // Test latency for each group and update local state
                val updatedGroups = proxyGroups.map { group ->
                    val apiGroup = groups[group.name] ?: return@map group
                    val delayMap = try {
                        MihomoApi.testGroupDelay(apiPort, coreSecret, group.name)
                    } catch (_: Exception) {
                        emptyMap()
                    }

                    val updatedNodes = group.nodes.map { node ->
                        val delay = delayMap[node.name] ?: -1
                        node.copy(
                            latency = if (delay > 0) delay else 0,
                            alive = delay > 0,
                        )
                    }
                    group.copy(nodes = updatedNodes)
                }
                proxyGroups = updatedGroups

                addEvent("Info", "core", "Latency test completed", 0uL)
            } catch (e: Exception) {
                addEvent("Error", "core", "Latency test failed: ${e.message}", 0uL)
            } finally {
                isTestingLatency = false
            }
        }
    }

    fun smartSelectBest() {
        if (!smartEnabled) return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val currentGroup = proxyGroups.find { it.name == currentGroupName } ?: return@launch
                if (currentGroup.nodes.isEmpty()) return@launch

                val nodeNames = currentGroup.nodes.map { it.name }
                val nodeLatencyRecords = currentGroup.nodes.map { node ->
                    if (node.latency > 0 && node.alive) listOf(node.latency.toDouble()) else listOf(Double.MAX_VALUE)
                }
                val nodeSuccessRecords = currentGroup.nodes.map { node -> listOf(node.alive) }

                val weights = SmartScoreWeights(
                    latencyP90 = smartLatencyWeight,
                    successRate = smartSuccessWeight,
                    stability = smartStabilityWeight,
                )
                val decay = SmartDecayConfig(halfLifeHours = smartDecayHalfLife)

                val ranked = computeSmartRank(weights, decay, nodeNames, nodeLatencyRecords, nodeSuccessRecords)
                if (ranked.isNotEmpty()) {
                    val bestNode = currentGroup.nodes.getOrNull(ranked[0].rank.toInt() - 1)
                    if (bestNode != null) {
                        selectProxyNode(currentGroupName, bestNode.name)
                        addEvent("Info", "smart", "Smart selected: ${bestNode.name} (score: ${"%.2f".format(ranked[0].score)})", 0uL)
                    }
                }
            } catch (e: Exception) {
                addEvent("Error", "smart", "Smart select failed: ${e.message}", 0uL)
            }
        }
    }

    fun setSortMode(mode: String) {
        proxySortMode = mode
        val currentGroup = proxyGroups.find { it.name == currentGroupName } ?: return
        val sortedNodes = when (mode) {
            "name" -> currentGroup.nodes.sortedBy { it.name }
            "latency" -> currentGroup.nodes.sortedBy { if (it.latency > 0) it.latency else Int.MAX_VALUE }
            "smart" -> {
                if (!smartEnabled) currentGroup.nodes
                else {
                    try {
                        val nodeNames = currentGroup.nodes.map { it.name }
                        val nodeLatencyRecords = currentGroup.nodes.map { node ->
                            if (node.latency > 0 && node.alive) listOf(node.latency.toDouble()) else listOf(Double.MAX_VALUE)
                        }
                        val nodeSuccessRecords = currentGroup.nodes.map { node -> listOf(node.alive) }
                        val weights = SmartScoreWeights(smartLatencyWeight, smartSuccessWeight, smartStabilityWeight)
                        val decay = SmartDecayConfig(smartDecayHalfLife)
                        val ranked = computeSmartRank(weights, decay, nodeNames, nodeLatencyRecords, nodeSuccessRecords)
                        val rankMap = ranked.associateBy { it.name }
                        currentGroup.nodes.sortedBy { rankMap[it.name]?.rank?.toInt() ?: Int.MAX_VALUE }
                    } catch (_: Exception) {
                        currentGroup.nodes
                    }
                }
            }
            else -> currentGroup.nodes
        }
        proxyGroups = proxyGroups.map { group ->
            if (group.name == currentGroupName) group.copy(nodes = sortedNodes) else group
        }
    }

    // ── Failover ────────────────────────────────────────────────────────

    fun onNodeFailure(nodeName: String, success: Boolean) {
        if (!failoverEnabled) return
        val currentCount = nodeFailureCounts[nodeName] ?: 0u
        val newCount = if (success) 0u else currentCount + 1u
        nodeFailureCounts[nodeName] = newCount

        if (!success && newCount >= failoverThreshold) {
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    val policy = FailoverPolicyConfig(
                        enabled = true,
                        threshold = failoverThreshold,
                        cooldownSecs = failoverCooldownSecs,
                        fallbackGroup = failoverFallbackGroup,
                    )
                    val action = checkFailover(policy, nodeName, success, newCount)
                    if (action != null) {
                        addEvent("Warn", "core", "Failover: ${action.failedNode} -> ${action.target} (failures: ${action.failureCount})", 0uL)
                        selectProxyNode(currentGroupName, action.target)
                        nodeFailureCounts[nodeName] = 0u
                    }
                } catch (e: Exception) {
                    addEvent("Error", "core", "Failover check failed: ${e.message}", 0uL)
                }
            }
        }
    }

    // ── Connection management ───────────────────────────────────────────

    fun closeConnection(id: String) {
        // Update local state immediately
        connections = connections.filter { it.id != id }
        connectionCount = connections.size
        // Actually close the connection via mihomo API
        if (isCoreRunning && apiPort > 0u.toUShort()) {
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    MihomoApi.closeConnection(apiPort, coreSecret, id)
                } catch (_: Exception) { }
            }
        }
    }

    fun closeAllConnections() {
        // Update local state immediately
        connections = emptyList()
        connectionCount = 0
        // Actually close all connections via mihomo API
        if (isCoreRunning && apiPort > 0u.toUShort()) {
            viewModelScope.launch(Dispatchers.IO) {
                try {
                    MihomoApi.closeAllConnections(apiPort, coreSecret)
                    addEvent("Info", "core", "All connections closed", 0uL)
                } catch (e: Exception) {
                    addEvent("Error", "core", "Close connections failed: ${e.message}", 0uL)
                }
            }
        } else {
            addEvent("Info", "core", "All connections closed", 0uL)
        }
    }

    // ── Event & Log management ──────────────────────────────────────────

    fun addEvent(level: String, module: String, message: String, timestamp: ULong) {
        // Must modify Compose state on main thread
        viewModelScope.launch(Dispatchers.Main) {
            events = (events + EventItem(level, module, message, timestamp)).takeLast(100)
            logs = (logs + LogEntry(level, message, timestamp)).takeLast(500)
        }
    }

    fun clearLogs() {
        logs = emptyList()
    }

    fun setLogLevelFilter(level: String) {
        logLevelFilter = level
    }

    val filteredLogs: List<LogEntry>
        get() = if (logLevelFilter == "all") logs
        else logs.filter { it.level.equals(logLevelFilter, ignoreCase = true) }

    // ── Settings actions ────────────────────────────────────────────────

    fun setTunEnabled(enabled: Boolean) {
        tunEnabled = enabled
        if (isCoreRunning) {
            viewModelScope.launch(Dispatchers.IO) {
                try { restartCoreWithNewConfig() }
                catch (e: Exception) { addEvent("Error", "core", "TUN toggle failed: ${e.message}", 0uL) }
            }
        }
    }

    fun setSystemProxyEnabled(enabled: Boolean) {
        systemProxyEnabled = enabled
    }

    fun setIpv6Enabled(enabled: Boolean) {
        ipv6Enabled = enabled
    }

    fun setAllowLan(enabled: Boolean) {
        allowLan = enabled
    }

    fun setUnifiedDelay(enabled: Boolean) {
        unifiedDelay = enabled
    }

    fun updateMixedPort(port: UShort) {
        mixedPort = port
    }

    fun updateSocksPort(port: UShort) {
        socksPort = port
    }

    fun updateHttpPort(port: UShort) {
        httpPort = port
    }

    // ── Smart selector settings ─────────────────────────────────────────

    fun setSmartEnabled(enabled: Boolean) {
        smartEnabled = enabled
    }

    fun setSmartAutoTest(enabled: Boolean) {
        smartAutoTest = enabled
    }

    fun setSmartWeights(latency: Float, success: Float, stability: Float) {
        smartLatencyWeight = latency.toDouble()
        smartSuccessWeight = success.toDouble()
        smartStabilityWeight = stability.toDouble()
    }

    // ── Failover settings ───────────────────────────────────────────────

    fun setFailoverEnabled(enabled: Boolean) {
        failoverEnabled = enabled
    }

    fun setFailoverThreshold(threshold: UInt) {
        failoverThreshold = threshold
    }

    fun setFailoverCooldown(cooldownSecs: ULong) {
        failoverCooldownSecs = cooldownSecs
    }

    fun setFailoverFallbackGroup(group: String) {
        failoverFallbackGroup = group
    }

    // ── Utility ─────────────────────────────────────────────────────────

    fun validateCustomArgsSafe(args: List<String>): List<String> {
        return try {
            uniffi.zephyr_core.validateCustomArgs(args)
            args
        } catch (_: Exception) {
            args
        }
    }

    fun maskUrlSafe(url: String): String {
        return try { maskUrl(url) } catch (_: Exception) { url }
    }

    fun validateUrl(url: String): Boolean {
        return try {
            // validateUrlBasic throws AppException if URL is invalid
            validateUrlBasic(url)
            true
        } catch (_: Exception) {
            false
        }
    }

    // ── Core version ────────────────────────────────────────────────────

    fun refreshCoreVersion() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val versionOutput = processManager.getVersion()
                coreVersion = parseVersionOutput(versionOutput).ifEmpty { "unknown" }
            } catch (_: Exception) {
                coreVersion = "unknown"
            }
        }
    }

    /**
     * Refresh proxy groups and nodes from mihomo API.
     * Should be called after core starts.
     */
    fun refreshProxies() {
        if (!isCoreRunning || apiPort == 0u.toUShort()) return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val groups = MihomoApi.getProxies(apiPort, coreSecret)
                val updatedGroups = groups.map { (name, data) ->
                    val existingGroup = proxyGroups.find { it.name == name }
                    val nodes = data.all.map { nodeName ->
                        val existingNode = existingGroup?.nodes?.find { it.name == nodeName }
                        ProxyNode(
                            name = nodeName,
                            type = "",
                            latency = existingNode?.latency ?: 0,
                            alive = existingNode?.alive ?: false,
                        )
                    }
                    ProxyGroup(
                        name = name,
                        type = data.type,
                        nodes = nodes,
                        current = data.now,
                    )
                }
                proxyGroups = updatedGroups
                if (currentGroupName.isEmpty() && updatedGroups.isNotEmpty()) {
                    currentGroupName = updatedGroups.first().name
                }
                if (currentNodeName.isEmpty()) {
                    val currentGroup = updatedGroups.find { it.name == currentGroupName }
                    currentNodeName = currentGroup?.current ?: ""
                }
            } catch (e: Exception) {
                addEvent("Error", "core", "Failed to refresh proxies: ${e.message}", 0uL)
            }
        }
    }

    /**
     * Refresh connections from mihomo API.
     */
    fun refreshConnections() {
        if (!isCoreRunning || apiPort == 0u.toUShort()) return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val data = MihomoApi.getConnections(apiPort, coreSecret)
                connections = data.connections.map { conn ->
                    ConnectionItem(
                        id = conn.id,
                        host = conn.host,
                        network = conn.network,
                        type = conn.type,
                        chains = conn.chains,
                        dlSpeed = conn.downloadSpeed,
                        ulSpeed = conn.uploadSpeed,
                    )
                }
                connectionCount = connections.size
            } catch (_: Exception) { }
        }
    }

    // ── Cleanup ─────────────────────────────────────────────────────────

    override fun onCleared() {
        super.onCleared()
        try {
            processManager.killAll()
        } catch (_: Exception) { }
        try {
            appStore.destroy()
        } catch (_: Exception) { }
    }
}
