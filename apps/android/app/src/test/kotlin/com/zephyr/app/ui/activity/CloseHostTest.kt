package com.zephyr.app.ui.activity

import com.zephyr.engine.ConnectionInfo
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import java.lang.reflect.Proxy

class CloseHostTest {
    private class Fake(val conns: List<ConnectionInfo>, val failing: Set<String>) :
        ZephyrEngine by (Proxy.newProxyInstance(ZephyrEngine::class.java.classLoader, arrayOf(ZephyrEngine::class.java)) { _, m, _ ->
            throw UnsupportedOperationException(m.name)
        } as ZephyrEngine) {
        val closed = mutableListOf<String>()
        override fun activeConnections(): Flow<List<ConnectionInfo>> = flowOf(conns)
        override suspend fun closeConnection(id: String) {
            if (id in failing) throw ZephyrException(ErrorCode.NOT_RUNNING)
            closed += id
        }
    }

    private fun c(id: String, host: String) = ConnectionInfo(id, host, node = "n", upBytes = 0, downBytes = 0, startedAt = 0)

    @Test fun messages() {
        assertEquals("已关闭 3 个连接", closeMessage(3, 3))
        assertEquals("2 个连接未能关闭", closeMessage(1, 3))
        assertEquals("连接未能关闭", closeMessage(0, 2))
        assertEquals("没有活动的连接", closeMessage(0, 0))
    }

    @Test fun closesOnlyThatHost() = runTest {
        val e = Fake(listOf(c("1", "a.com"), c("2", "b.com"), c("3", "a.com")), failing = emptySet())
        assertEquals("已关闭 2 个连接", closeHostConnections(e, "a.com"))
        assertEquals(listOf("1", "3"), e.closed)
    }

    @Test fun partialFailure() = runTest {
        val e = Fake(listOf(c("1", "a.com"), c("3", "a.com")), failing = setOf("3"))
        assertEquals("1 个连接未能关闭", closeHostConnections(e, "a.com"))
    }
}
