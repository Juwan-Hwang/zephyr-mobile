package com.zephyr.app.ui.nav

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute
import com.zephyr.design.theme.ZAnim
import kotlin.math.roundToInt

/**
 * Page push / pop motion for the root NavHost (#208, real-device feedback: back "缩小到中间，停顿，然后突然消失").
 *
 * Root cause of the old feel: Navigation Compose 2.8+ seeks a separate pair of transitions while a predictive-back
 * gesture is in flight — `predictivePopEnterTransition` / `predictivePopExitTransition` — and we never set them, so
 * every edge swipe ran the library default: the top page `scaleOut(0.7f)` toward the centre with no fade (the
 * shrink), a spring whose seek fraction stalls near the end (the pause), then the entry is dropped at full opacity
 * (the cut). Our own popEnter / popExit were only used by the on-screen "‹" link.
 *
 * Now (iOS-like, matching the prototype's `.pg` slide):
 * - push: the new page slides in from the end edge over the full width; the page below drifts [PARALLAX] toward the
 *   start edge and dims.
 * - pop (link or committed gesture): the exact mirror.
 * - predictive back: the same pop, but on [LinearEasing] so the seeked offset is proportional to the gesture
 *   progress — the page follows the finger from the edge it was swiped from; on release NavHost runs the rest of
 *   the same transition (no hold), on cancel it seeks back to 0.
 * - reduced motion (animator scale 0, i.e. 移除动画): a short cross-fade instead of any movement.
 *
 * The pure maths ([exitSign], [underOffset], [trackedOffset]) is unit-tested in NavMotionTest.
 */
internal object NavMotion {
    const val PUSH_MS = 300
    const val POP_MS = 250
    /** Predictive pop: linear, so a committed gesture finishes the remaining distance in ≤ this. */
    const val PREDICTIVE_MS = 300
    const val FADE_MS = 150
    /** How far the page underneath moves, as a fraction of the width (iOS ≈ 0.3). */
    const val PARALLAX = 0.25f
    /** Alpha of the page underneath while covered (a light dim against the shared background). */
    const val UNDER_ALPHA = 0.6f

    // androidx.navigationevent.NavigationEvent swipe edges (navigationevent is runtime-only on our classpath).
    const val EDGE_LEFT = 0
    const val EDGE_RIGHT = 1
    const val EDGE_NONE = 2

    /**
     * Physical x direction (+1 right, -1 left) the top page leaves toward on pop. A gesture from the left edge pushes
     * it right, one from the right edge pushes it left; with no edge (button / link) it returns toward the end edge.
     * [layoutSign] is [com.zephyr.app.ui.common.startToEndSign] (+1 LTR, -1 RTL).
     */
    fun exitSign(swipeEdge: Int, layoutSign: Int): Int = when (swipeEdge) {
        EDGE_LEFT -> 1
        EDGE_RIGHT -> -1
        else -> layoutSign
    }

    /** Offset of the top page fully off-screen. */
    fun topOffset(width: Int, sign: Int): Int = sign * width

    /** Offset of the page underneath while covered: [PARALLAX] of the width, opposite the top page. */
    fun underOffset(width: Int, sign: Int): Int = -sign * (width * PARALLAX).roundToInt()

    /** Where the top page sits at gesture [progress] (what seeking a linear transition produces). */
    fun trackedOffset(progress: Float, width: Int, sign: Int): Int = (progress.coerceIn(0f, 1f) * topOffset(width, sign)).roundToInt()

}

private fun NavBackStackEntry.isToday() = destination.hasRoute<Today>()
private fun NavBackStackEntry.isOnboarding() = destination.hasRoute<Onboarding>()

/** Builds the NavHost transitions for one layout direction / motion setting. */
internal class NavTransitions(private val dir: Int, private val reduced: Boolean) {
    private val fadeInT get() = fadeIn(tween(NavMotion.FADE_MS, easing = ZAnim.EaseOut))
    private val fadeOutT get() = fadeOut(tween(NavMotion.FADE_MS, easing = ZAnim.EaseOut))

    val enter: AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = {
        when {
            reduced || initialState.isOnboarding() -> fadeInT
            // 今日 is a full-screen card that rises from below (prototype), not a pushed page.
            targetState.isToday() -> slideInVertically(tween(NavMotion.PUSH_MS, easing = ZAnim.EaseInOut)) { it / 3 } + fadeInT
            else -> slideInHorizontally(tween(NavMotion.PUSH_MS, easing = ZAnim.EaseInOut)) { NavMotion.topOffset(it, dir) }
        }
    }

    val exit: AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = {
        when {
            reduced || targetState.isToday() -> fadeOutT
            else -> slideOutHorizontally(tween(NavMotion.PUSH_MS, easing = ZAnim.EaseInOut)) { NavMotion.underOffset(it, dir) } +
                fadeOut(tween(NavMotion.PUSH_MS, easing = ZAnim.EaseInOut), targetAlpha = NavMotion.UNDER_ALPHA)
        }
    }

    val popEnter: AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = { under(dir, NavMotion.POP_MS, ZAnim.EaseInOut) }

    val popExit: AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = { top(dir, NavMotion.POP_MS, ZAnim.EaseInOut) }

    /** Seeked by the gesture: linear, so the offset is proportional to the back progress. */
    val predictivePopEnter: AnimatedContentTransitionScope<NavBackStackEntry>.(Int) -> EnterTransition = { edge ->
        under(NavMotion.exitSign(edge, dir), NavMotion.PREDICTIVE_MS, LinearEasing)
    }

    val predictivePopExit: AnimatedContentTransitionScope<NavBackStackEntry>.(Int) -> ExitTransition = { edge ->
        top(NavMotion.exitSign(edge, dir), NavMotion.PREDICTIVE_MS, LinearEasing)
    }

    private fun AnimatedContentTransitionScope<NavBackStackEntry>.under(sign: Int, ms: Int, easing: Easing): EnterTransition = when {
        reduced -> fadeInT
        // Back from 今日 (which drops down): the page underneath only fades back up.
        initialState.isToday() -> fadeIn(tween(ms, easing = easing), initialAlpha = NavMotion.UNDER_ALPHA)
        else -> slideInHorizontally(tween(ms, easing = easing)) { NavMotion.underOffset(it, sign) } +
            fadeIn(tween(ms, easing = easing), initialAlpha = NavMotion.UNDER_ALPHA)
    }

    private fun AnimatedContentTransitionScope<NavBackStackEntry>.top(sign: Int, ms: Int, easing: Easing): ExitTransition = when {
        reduced -> fadeOutT
        initialState.isToday() -> slideOutVertically(tween(ms, easing = easing)) { it / 3 } + fadeOut(tween(ms, easing = easing))
        else -> slideOutHorizontally(tween(ms, easing = easing)) { NavMotion.topOffset(it, sign) }
    }
}
