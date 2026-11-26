package com.zephyr.app.ui.subs

import com.zephyr.app.R
import com.zephyr.app.ui.common.UiText
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ImportItem
import com.zephyr.engine.ImportSource
import com.zephyr.engine.Subscription
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Contract §22.a on 订阅 (iOS SubscriptionsActiveTests): tap a row → it becomes the active (first) subscription. */
class ActiveSubscriptionTest {
    /** Counts engine calls so "tap on the active one" can prove it never reaches the engine. */
    private class Counting(val m: MockEngine) : ZephyrEngine by m {
        var calls = 0
        override suspend fun setActiveSubscription(id: String): List<Subscription> { calls++; return m.setActiveSubscription(id) }
    }

    private fun engine() = Counting(MockEngine(clock = { 0L }, latencyScale = 0.0))

    @Test fun currentSubscriptionIsFirstAndFallsBack() = runBlocking {
        val e = engine()
        val subs = e.subscriptions().first()
        assertEquals(subs[0].id, ActiveSubscription.activeId(subs))
        e.deleteSubscription(subs[0].id)
        assertEquals("deleting the active one falls back to the next", subs[1].id, ActiveSubscription.activeId(e.subscriptions().first()))
        assertNull(ActiveSubscription.activeId(emptyList()))
    }

    @Test fun tapSetsActiveSubscription() = runBlocking {
        val e = engine()
        e.importItem(ImportSource.URL, ImportItem("Third", "https://third.example.com/sub", null))
        val subs = e.subscriptions().first()
        val before = subs.map { it.id }
        val target = subs[2]
        val r = ActiveSubscription.activate(e, subs, target)
        assertTrue(r is ActiveSubscription.Outcome.Switched)
        val expected = listOf(target.id) + before.filter { it != target.id }
        assertEquals(expected, (r as ActiveSubscription.Outcome.Switched).subscriptions.map { it.id })
        val streamed = e.subscriptions().first()
        assertEquals("the list the page shows follows", expected, streamed.map { it.id })
        assertEquals(target.id, ActiveSubscription.activeId(streamed))
    }

    @Test fun tapOnActiveSubscriptionDoesNothing() = runBlocking {
        val e = engine()
        val subs = e.subscriptions().first()
        assertEquals(ActiveSubscription.Outcome.Unchanged, ActiveSubscription.activate(e, subs, subs[0]))
        assertEquals(0, e.calls)
        assertEquals(subs.map { it.id }, e.subscriptions().first().map { it.id })
    }

    /** Gone (e.g. deleted elsewhere) → subscription_not_found with its typed copy; the list stays. */
    @Test fun activateMissingSubscriptionShowsTypedError() = runBlocking {
        val e = engine()
        val subs = e.subscriptions().first()
        val r = ActiveSubscription.activate(e, subs, Subscription(id = "gone", name = "Gone", nodeCount = 1))
        assertEquals(ActiveSubscription.Outcome.Failed(ErrorCode.SUBSCRIPTION_NOT_FOUND), r)
        assertEquals(UiText.Res(R.string.home_failure_no_subscription), ActiveSubscription.errorText(ErrorCode.SUBSCRIPTION_NOT_FOUND, "Gone"))
        assertEquals(UiText.Res(R.string.subs_error_activate, listOf("Gone")), ActiveSubscription.errorText(ErrorCode.CORE_CRASHED, "Gone"))
        assertEquals(subs.map { it.id }, e.subscriptions().first().map { it.id })
    }
}
