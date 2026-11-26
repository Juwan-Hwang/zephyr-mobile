package com.zephyr.app.ui.home

import com.zephyr.engine.NodeFunnel
import com.zephyr.engine.ScanProgress
import com.zephyr.engine.Scene
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.mock.MockEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * #208 bug 3 (S25 Ultra, live core): after 重新检测 the funnel kept 已测速 0 · 可连通 0 · 低于 300ms 0. The live
 * retestScene writes node latencies but leaves the scene's testedAt alone (it is the exit-trace time), and the row's
 * funnel was only re-read when testedAt moved. The mock bumps testedAt on every retest, which hid it.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RetestFunnelTest {
    private val main = UnconfinedTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(main)
    @After fun tearDown() = Dispatchers.resetMain()

    /** Behaves like CoreEngine with the core running: latencies recorded, testedAt unchanged. */
    private class LiveLike(private val m: MockEngine) : ZephyrEngine by m {
        @Volatile var measured = 0L
        val scan = MutableStateFlow<ScanProgress?>(null)
        override fun scanProgress(): Flow<ScanProgress?> = scan
        override suspend fun retestScene(sceneId: String): Scene {
            val before = m.scenes().first().first { it.id == sceneId }
            scan.value = ScanProgress(0, 128)
            measured = 64; scan.value = ScanProgress(64, 128)
            measured = 128; scan.value = ScanProgress(128, 128)
            scan.value = null
            return before
        }
        override suspend fun sceneFunnel(sceneId: String, maxAgeMs: Long, thresholdMs: Int) =
            NodeFunnel(sourceCount = 1, poolSize = 128, tested = measured, reachable = measured * 3 / 4, underThreshold = measured / 2, thresholdMs = thresholdMs)
    }

    @Test fun retestRereadsTheFunnelEvenWhenTestedAtDoesNotMove() = runBlocking {
        val e = LiveLike(MockEngine(demo = true, compute = Dispatchers.Unconfined))
        val vm = HomeViewModel(e)
        val scene = e.scenes().first().first()
        vm.prefetchFunnel(scene); main.scheduler.runCurrent()
        assertEquals(0L, vm.ui.value.funnels.getValue(scene.id).tested)

        vm.retest(scene.id); main.scheduler.runCurrent()

        val f = vm.ui.value.funnels.getValue(scene.id)
        assertEquals(128L, f.tested)
        assertEquals(96L, f.reachable)
        assertEquals(64L, f.underThreshold)
        assertEquals(emptySet<String>(), vm.retesting.value)
    }
}
