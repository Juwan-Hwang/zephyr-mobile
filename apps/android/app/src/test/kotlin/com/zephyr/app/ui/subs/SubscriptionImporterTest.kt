package com.zephyr.app.ui.subs

import com.zephyr.engine.ImportItem
import com.zephyr.engine.ImportPayload
import com.zephyr.engine.ImportPayloads
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
        override fun parseImportPayload(payload: String): ImportPayload = ImportPayloads.parse(payload)
        override suspend fun importItem(source: ImportSource, item: ImportItem): Subscription = result.await()
        override suspend fun deleteSubscription(id: String) { deleted += id }
    }

    private companion object { fun sub(id: String) = Subscription(id = id, name = id, nodeCount = 3) }

    @Test fun completesNormally() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(emptyList(), r)
        var got: Subscription? = null
        val imp = SubscriptionImporter(this, null, { { got = it.first } }, { e })
        imp.submit(ImportSource.URL, "https://x.example.com/s"); assertTrue(imp.busy)
        r.complete(sub("new")); advanceUntilIdle()
        assertEquals("new", got?.id); assertFalse(imp.busy); assertTrue(e.deleted.isEmpty())
    }

    @Test fun cancelDropsLateResultAndWithdrawsNewSubscription() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(listOf("old"), r)
        var got: Subscription? = null
        val imp = SubscriptionImporter(this, null, { { got = it.first } }, { e })
        imp.submit(ImportSource.URL, "https://x.example.com/s"); advanceUntilIdle()
        imp.cancel(); assertFalse(imp.busy)
        r.complete(sub("new")); advanceUntilIdle()
        assertNull(got); assertEquals(listOf("new"), e.deleted); assertFalse(imp.busy)
    }

    @Test fun cancelKeepsPreExistingSubscription() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(listOf("old"), r)
        val imp = SubscriptionImporter(this, null, { { } }, { e })
        imp.submit(ImportSource.URL, "https://x.example.com/s"); advanceUntilIdle()
        imp.cancel(); r.complete(sub("old")); advanceUntilIdle()
        assertTrue(e.deleted.isEmpty())
    }

    @Test fun cancelWhenIdleIsNoOp() = runTest {
        val imp = SubscriptionImporter(this, null, { { } }, { FakeEngine(emptyList(), CompletableDeferred()) })
        imp.cancel(); assertFalse(imp.busy); assertNull(imp.error)
    }

    /** Contract §15: a desktop sync code with several subscriptions is listed first, then each item is imported. */
    @Test fun batchCodeWaitsForConfirmation() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(emptyList(), r)
        var got: ImportResult? = null
        val imp = SubscriptionImporter(this, null, { { got = it } }, { e })
        val code = "zephyr://import?v=1&d=eyJ2IjoxLCJzdWJzIjpbeyJuYW1lIjoiTmVidWxhIENsb3VkIiwidXJsIjoiaHR0cHM6Ly9hLmV4YW1wbGUuY29tL3M_dG9rZW49MSJ9LHsidXJsIjoiaHR0cHM6Ly9iLmV4YW1wbGUuY29tL3MiLCJhdXRvIjoyNH1dfQ"
        imp.submit(ImportSource.QR, code)
        assertFalse(imp.busy); assertEquals(2, imp.pending?.payload?.items?.size); assertFalse(imp.pending!!.external)
        imp.confirm(); r.complete(sub("new")); advanceUntilIdle()
        assertNull(imp.pending); assertEquals(2, got?.subs?.size)
    }

    /** Audit U26: a link opened from another app is never imported without the user's confirmation. */
    @Test fun deepLinkIsOfferedNotImported() = runTest {
        val r = CompletableDeferred<Subscription>(); val e = FakeEngine(emptyList(), r)
        val imp = SubscriptionImporter(this, null, { { } }, { e })
        imp.offer("clashmeta://install-config?url=http%3A%2F%2Fx.example.com%2Fs")
        assertFalse(imp.busy); assertTrue(imp.pending!!.external); assertTrue(imp.pending!!.insecure)
        imp.dismissPending(); assertNull(imp.pending)
    }

    @Test fun newerImportCodeAsksToUpdate() = runTest {
        val imp = SubscriptionImporter(this, null, { { } }, { FakeEngine(emptyList(), CompletableDeferred()) })
        imp.submit(ImportSource.QR, "zephyr://import?v=2&url=https%3A%2F%2Fa.example.com")
        assertEquals(com.zephyr.app.ui.common.uiText(com.zephyr.app.R.string.subs_error_import_version), imp.error)
        imp.submit(ImportSource.QR, "hello")
        assertEquals(com.zephyr.app.ui.common.uiText(com.zephyr.app.R.string.subs_error_invalid_link), imp.error)
    }
}
