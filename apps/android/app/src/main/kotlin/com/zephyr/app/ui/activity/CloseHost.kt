package com.zephyr.app.ui.activity

import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.flow.first

/**
 * Close every live connection to [host] (iOS H-P2-14 parity) and return the toast text:
 * "已关闭 n 个连接" / "n 个连接未能关闭" / "连接未能关闭", or "没有活动的连接" when nothing is open.
 */
suspend fun closeHostConnections(engine: ZephyrEngine, host: String): String {
    val ids = runCatching { engine.activeConnections().first() }.getOrDefault(emptyList()).filter { it.host == host }.map { it.id }
    var closed = 0
    for (id in ids) if (runCatching { engine.closeConnection(id) }.isSuccess) closed++
    return closeMessage(closed, ids.size)
}

fun closeMessage(closed: Int, total: Int): String = when {
    total == 0 -> "没有活动的连接"
    closed == total -> "已关闭 $closed 个连接"
    closed == 0 -> "连接未能关闭"
    else -> "${total - closed} 个连接未能关闭"
}
