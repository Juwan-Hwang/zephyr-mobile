package com.zephyr.engine.mock

import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ImportItem
import com.zephyr.engine.ImportSource
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/** Contract §22.a: MockEngine.setActiveSubscription has core's semantics (iOS SetActiveSubscriptionMockTests). */
class SetActiveSubscriptionMockTest {
    private fun engine() = MockEngine(clock = { 0L }, latencyScale = 0.0)

    @Test fun movesToFrontKeepingOrder() = runBlocking {
        val e = engine()
        e.importItem(ImportSource.URL, ImportItem("Third", "https://third.example.com/sub", null))
        val before = e.subscriptions().first().map { it.id }
        assertEquals(3, before.size)
        val target = before[2]
        val list = e.setActiveSubscription(target)
        assertEquals(listOf(target) + before.filter { it != target }, list.map { it.id })
        assertEquals("the stream carries the new order", list.map { it.id }, e.subscriptions().first().map { it.id })
        // Already first: order unchanged.
        assertEquals(list.map { it.id }, e.setActiveSubscription(target).map { it.id })
    }

    @Test fun missingIsSubscriptionNotFound() = runBlocking {
        val e = engine()
        val before = e.subscriptions().first().map { it.id }
        try { e.setActiveSubscription("nope"); fail("should throw") } catch (x: ZephyrException) {
            assertEquals(ErrorCode.SUBSCRIPTION_NOT_FOUND, x.code)
        }
        assertEquals(before, e.subscriptions().first().map { it.id })
    }

    @Test fun deletingTheActiveOneFallsBackToTheNext() = runBlocking {
        val e = engine()
        val before = e.subscriptions().first().map { it.id }
        e.setActiveSubscription(before[1])
        e.deleteSubscription(before[1])
        assertEquals(before[0], e.subscriptions().first().first().id)
    }
}
