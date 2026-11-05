package com.zephyr.app

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * mihomo RESTful API client.
 *
 * mihomo exposes a RESTful API at 127.0.0.1:{apiPort} with Bearer token auth.
 * This class provides typed Kotlin access to those endpoints.
 *
 * API reference: https://wiki.metacubex.one/api/
 */
object MihomoApi {
    private const val TAG = "MihomoApi"

    // ── Proxies ──────────────────────────────────────────────────────

    /**
     * Get all proxy groups and their nodes.
     * GET /proxies
     * Returns: Map of group name -> ProxyGroupData
     */
    suspend fun getProxies(apiPort: UShort, secret: String): Map<String, ProxyGroupData> = withContext(Dispatchers.IO) {
        val json = get(apiPort, secret, "/proxies")
        val proxies = json.getJSONObject("proxies")
        val result = mutableMapOf<String, ProxyGroupData>()
        val keys = proxies.keys()
        while (keys.hasNext()) {
            val name = keys.next()
            val proxy = proxies.getJSONObject(name)
            val type = proxy.optString("type", "")
            // Only include groups (Selector, URLTest, Fallback)
            if (type in listOf("Selector", "URLTest", "Fallback", "LoadBalance")) {
                val allNodes = proxy.optJSONArray("all")?.let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }
                } ?: emptyList()
                val now = proxy.optString("now", "")
                result[name] = ProxyGroupData(name = name, type = type, all = allNodes, now = now)
            }
        }
        result
    }

    /**
     * Select a proxy node in a group.
     * PUT /proxies/{groupName}
     * Body: {"name": "nodeName"}
     */
    suspend fun selectProxy(apiPort: UShort, secret: String, groupName: String, nodeName: String) = withContext(Dispatchers.IO) {
        put(apiPort, secret, "/proxies/${encode(groupName)}", JSONObject().put("name", nodeName))
    }

    /**
     * Test proxy node latency.
     * GET /proxies/{nodeName}/delay?timeout=5000&url=https://www.gstatic.com/generate_204
     * Returns: delay in ms, or -1 if timeout/error
     */
    suspend fun testProxyDelay(apiPort: UShort, secret: String, nodeName: String): Int = withContext(Dispatchers.IO) {
        try {
            val json = get(apiPort, secret, "/proxies/${encode(nodeName)}/delay?timeout=5000&url=https://www.gstatic.com/generate_204")
            json.optInt("delay", -1)
        } catch (e: Exception) {
            -1
        }
    }

    /**
     * Test all proxies in a group for latency.
     * GET /group/{groupName}/delay?timeout=5000&url=https://www.gstatic.com/generate_204
     */
    suspend fun testGroupDelay(apiPort: UShort, secret: String, groupName: String): Map<String, Int> = withContext(Dispatchers.IO) {
        try {
            val json = get(apiPort, secret, "/group/${encode(groupName)}/delay?timeout=5000&url=https://www.gstatic.com/generate_204")
            val result = mutableMapOf<String, Int>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val name = keys.next()
                val obj = json.getJSONObject(name)
                result[name] = obj.optInt("delay", -1)
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }

    // ── Connections ──────────────────────────────────────────────────

    /**
     * Get all active connections.
     * GET /connections
     */
    suspend fun getConnections(apiPort: UShort, secret: String): ConnectionsData = withContext(Dispatchers.IO) {
        val json = get(apiPort, secret, "/connections")
        val connections = json.optJSONArray("connections")?.let { arr ->
            (0 until arr.length()).map { i ->
                val conn = arr.getJSONObject(i)
                val metadata = conn.getJSONObject("metadata")
                ConnectionData(
                    id = conn.optString("id", ""),
                    host = metadata.optString("host", "") + ":" + metadata.optString("destinationPort", ""),
                    network = metadata.optString("network", ""),
                    type = metadata.optString("type", ""),
                    chains = conn.optJSONArray("chains")?.let { a -> (0 until a.length()).joinToString("->") { a.getString(it) } } ?: "",
                    downloadSpeed = conn.optLong("download", 0).toULong(),
                    uploadSpeed = conn.optLong("upload", 0).toULong(),
                )
            }
        } ?: emptyList()
        ConnectionsData(
            connections = connections,
            downloadTotal = json.optLong("downloadTotal", 0).toULong(),
            uploadTotal = json.optLong("uploadTotal", 0).toULong(),
        )
    }

    /**
     * Close a specific connection.
     * DELETE /connections/{id}
     */
    suspend fun closeConnection(apiPort: UShort, secret: String, id: String) = withContext(Dispatchers.IO) {
        delete(apiPort, secret, "/connections/$id")
    }

    /**
     * Close all connections.
     * DELETE /connections
     */
    suspend fun closeAllConnections(apiPort: UShort, secret: String) = withContext(Dispatchers.IO) {
        delete(apiPort, secret, "/connections")
    }

    // ── Config ───────────────────────────────────────────────────────

    /**
     * Get current config.
     * GET /configs
     */
    suspend fun getConfig(apiPort: UShort, secret: String): JSONObject = withContext(Dispatchers.IO) {
        get(apiPort, secret, "/configs")
    }

    /**
     * Update running config (patch).
     * PATCH /configs
     */
    suspend fun patchConfig(apiPort: UShort, secret: String, config: JSONObject) = withContext(Dispatchers.IO) {
        patch(apiPort, secret, "/configs", config)
    }

    // ── Data classes ─────────────────────────────────────────────────

    data class ProxyGroupData(
        val name: String,
        val type: String,
        val all: List<String>,
        val now: String,
    )

    data class ConnectionsData(
        val connections: List<ConnectionData>,
        val downloadTotal: ULong,
        val uploadTotal: ULong,
    )

    data class ConnectionData(
        val id: String,
        val host: String,
        val network: String,
        val type: String,
        val chains: String,
        val downloadSpeed: ULong,
        val uploadSpeed: ULong,
    )

    // ── HTTP helpers ─────────────────────────────────────────────────

    private fun encode(s: String): String = java.net.URLEncoder.encode(s, "UTF-8")

    private fun get(apiPort: UShort, secret: String, path: String): JSONObject {
        val url = URL("http://127.0.0.1:$apiPort$path")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.setRequestProperty("Authorization", "Bearer $secret")
        conn.connectTimeout = 5000
        conn.readTimeout = 10000
        val response = conn.inputStream.bufferedReader().readText()
        conn.disconnect()
        return JSONObject(response)
    }

    private fun put(apiPort: UShort, secret: String, path: String, body: JSONObject) {
        val url = URL("http://127.0.0.1:$apiPort$path")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "PUT"
        conn.doOutput = true
        conn.setRequestProperty("Authorization", "Bearer $secret")
        conn.setRequestProperty("Content-Type", "application/json")
        conn.connectTimeout = 5000
        conn.outputStream.use { it.write(body.toString().toByteArray()) }
        conn.responseCode // Force the request
        conn.disconnect()
    }

    private fun delete(apiPort: UShort, secret: String, path: String) {
        val url = URL("http://127.0.0.1:$apiPort$path")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "DELETE"
        conn.setRequestProperty("Authorization", "Bearer $secret")
        conn.connectTimeout = 5000
        conn.responseCode // Force the request
        conn.disconnect()
    }

    private fun patch(apiPort: UShort, secret: String, path: String, body: JSONObject) {
        val url = URL("http://127.0.0.1:$apiPort$path")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "PATCH"
        conn.doOutput = true
        conn.setRequestProperty("Authorization", "Bearer $secret")
        conn.setRequestProperty("Content-Type", "application/json")
        conn.connectTimeout = 5000
        conn.outputStream.use { it.write(body.toString().toByteArray()) }
        conn.responseCode // Force the request
        conn.disconnect()
    }
}
