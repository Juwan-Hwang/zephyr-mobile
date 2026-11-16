package com.zephyr.app.ui.activity

import com.zephyr.app.R
import com.zephyr.app.ui.common.uiPlural
import com.zephyr.app.ui.common.uiText
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

    // The toast is resolved where it is drawn; here we check which message and which count it carries.
    @Test fun messages() {
        assertEquals(uiPlural(R.plurals.activity_closed, 3), closeMessage(3, 3))
        assertEquals(uiPlural(R.plurals.activity_close_partial, 2), closeMessage(1, 3))
        assertEquals(uiPlural(R.plurals.activity_close_failed, 2), closeMessage(0, 2))
        assertEquals(uiText(R.string.activity_close_none), closeMessage(0, 0))
    }

    @Test fun closesOnlyThatHost() = runTest {
        val e = Fake(listOf(c("1", "a.com"), c("2", "b.com"), c("3", "a.com")), failing = emptySet())
        assertEquals(uiPlural(R.plurals.activity_closed, 2), closeHostConnections(e, "a.com"))
        assertEquals(listOf("1", "3"), e.closed)
    }

    @Test fun partialFailure() = runTest {
        val e = Fake(listOf(c("1", "a.com"), c("3", "a.com")), failing = setOf("3"))
        assertEquals(uiPlural(R.plurals.activity_close_partial, 1), closeHostConnections(e, "a.com"))
    }
}
