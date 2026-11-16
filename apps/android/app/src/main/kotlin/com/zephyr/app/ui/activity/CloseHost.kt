package com.zephyr.app.ui.activity

import com.zephyr.app.R
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiPlural
import com.zephyr.app.ui.common.uiText
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.flow.first

/**
 * Close every live connection to [host] (iOS H-P2-14 parity) and return the toast text:
 * "已关闭 n 个连接" / "n 个连接未能关闭" / "连接未能关闭", or "没有活动的连接" when nothing is open.
 */
suspend fun closeHostConnections(engine: ZephyrEngine, host: String): UiText {
    val ids = runCatching { engine.activeConnections().first() }.getOrDefault(emptyList()).filter { it.host == host }.map { it.id }
    var closed = 0
    for (id in ids) if (runCatching { engine.closeConnection(id) }.isSuccess) closed++
    return closeMessage(closed, ids.size)
}

fun closeMessage(closed: Int, total: Int): UiText = when {
    total == 0 -> uiText(R.string.activity_close_none)
    closed == total -> uiPlural(R.plurals.activity_closed, closed)
    closed == 0 -> uiPlural(R.plurals.activity_close_failed, total)
    else -> uiPlural(R.plurals.activity_close_partial, total - closed)
}
