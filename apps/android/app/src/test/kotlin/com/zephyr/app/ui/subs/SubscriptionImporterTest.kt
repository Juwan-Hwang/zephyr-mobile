package com.zephyr.app.ui.subs

import com.zephyr.engine.ImportSource
import com.zephyr.engine.Subscription
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Proxy

class SubscriptionImporterTest {
    private class FakeEngine(val existing: List<String>, val result: CompletableDeferred<Subscription>) :
        ZephyrEngine by (Proxy.newProxyInstance(ZephyrEngine::class.java.classLoader, arrayOf(ZephyrEngine::class.java)) { _, m, _ ->
            throw UnsupportedOperationException(m.name)
        } as ZephyrEngine) {
        val deleted = mutableListOf<String>()
        override fun subscriptions(): Flow<List<Subscription>> = flowOf(existing.map { sub(it) })
        override suspend fun importSubscription(source: ImportSource, payload: String): Subscription = result.await()
        override suspend fun deleteSubscription(id: String) { deleted += id }
    }

    private companion object { fun sub(id: String) = Subscription(id = id, name = id, nodeCount = 3) }

    @Test fun completesNormally() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(emptyList(), r)
        var got: Subscription? = null
        val imp = SubscriptionImporter(this, null, { { got = it } }, { e })
        imp.submit(ImportSource.URL, "https://x"); assertTrue(imp.busy)
        r.complete(sub("new")); advanceUntilIdle()
        assertEquals("new", got?.id); assertFalse(imp.busy); assertTrue(e.deleted.isEmpty())
    }

    @Test fun cancelDropsLateResultAndWithdrawsNewSubscription() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(listOf("old"), r)
        var got: Subscription? = null
        val imp = SubscriptionImporter(this, null, { { got = it } }, { e })
        imp.submit(ImportSource.URL, "https://x"); advanceUntilIdle()
        imp.cancel(); assertFalse(imp.busy)
        r.complete(sub("new")); advanceUntilIdle()
        assertNull(got); assertEquals(listOf("new"), e.deleted); assertFalse(imp.busy)
    }

    @Test fun cancelKeepsPreExistingSubscription() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(listOf("old"), r)
        val imp = SubscriptionImporter(this, null, { { } }, { e })
        imp.submit(ImportSource.URL, "https://x"); advanceUntilIdle()
        imp.cancel(); r.complete(sub("old")); advanceUntilIdle()
        assertTrue(e.deleted.isEmpty())
    }

    @Test fun cancelWhenIdleIsNoOp() = runTest {
        val imp = SubscriptionImporter(this, null, { { } }, { FakeEngine(emptyList(), CompletableDeferred()) })
        imp.cancel(); assertFalse(imp.busy); assertNull(imp.error)
    }
}
