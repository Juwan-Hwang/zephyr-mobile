package com.zephyr.app.ui.common

import com.zephyr.engine.NodeSummary
import org.junit.Assert.assertEquals
import org.junit.Test

class NodeSortingTest {
    private fun n(id: Long, name: String, ms: Int?) = NodeSummary(id = id, name = name, region = "JP", protocol = "vless", latencyMs = ms)

    private val rows = listOf(n(1, "Tokyo 02", null), n(2, "Osaka 01", 120), n(3, "Tokyo 01", -1), n(4, "Kyoto", 40), n(5, "Nagoya", null), n(6, "Sapporo", 120))

    @Test fun defaultKeepsTheSubscriptionOrder() = assertEquals(rows, NodeSorting.sort(rows, NodeSort.DEFAULT))

    @Test fun latencyPutsFastestFirstThenUntestedThenTimeouts() {
        // Equal readings keep their order (Osaka 01 before Sapporo); untested and timeouts go last.
        assertEquals(listOf(4L, 2L, 6L, 1L, 5L, 3L), NodeSorting.sort(rows, NodeSort.LATENCY).map { it.id })
    }

    @Test fun latencyUsesReadingsThatArrivedLater() {
        val later = mapOf(1L to 10, 4L to -1)
        assertEquals(listOf(1L, 2L, 6L, 5L, 3L, 4L), NodeSorting.sort(rows, NodeSort.LATENCY) { later[it.id] ?: it.latencyMs }.map { it.id })
    }

    @Test fun nameSortsAlphabetically() {
        assertEquals(listOf("Kyoto", "Nagoya", "Osaka 01", "Sapporo", "Tokyo 01", "Tokyo 02"), NodeSorting.sort(rows, NodeSort.NAME).map { it.name })
    }

    @Test fun storedValueParsesAndFallsBack() {
        assertEquals(NodeSort.LATENCY, NodeSort.parse("LATENCY"))
        assertEquals(NodeSort.DEFAULT, NodeSort.parse(null))
        assertEquals(NodeSort.DEFAULT, NodeSort.parse("fastest"))
    }
}
