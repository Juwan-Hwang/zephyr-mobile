package com.zephyr.app.ui.subs

import com.zephyr.app.R
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiText
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.Subscription
import com.zephyr.engine.ZephyrEngine
import com.zephyr.engine.ZephyrException

/**
 * Contract §22.a: the active subscription is the first in the list (core keeps it that way: the first one is used,
 * deleting it falls back to the next). Tapping a row on 订阅 makes it the active one; the platform keeps no id of its own.
 */
internal object ActiveSubscription {
    fun activeId(subs: List<Subscription>): String? = subs.firstOrNull()?.id

    sealed interface Outcome {
        /** Already the active one: no engine call, no reload. */
        data object Unchanged : Outcome
        data class Switched(val subscriptions: List<Subscription>) : Outcome
        data class Failed(val code: ErrorCode?) : Outcome
    }

    suspend fun activate(engine: ZephyrEngine, subs: List<Subscription>, target: Subscription): Outcome {
        if (activeId(subs) == target.id) return Outcome.Unchanged
        return try { Outcome.Switched(engine.setActiveSubscription(target.id)) } catch (e: ZephyrException) {
            Outcome.Failed(e.code)
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (_: Throwable) { Outcome.Failed(null) }
    }

    /** One line; `subscription_not_found` keeps its typed copy (iOS 先添加订阅), anything else names the subscription. */
    fun errorText(code: ErrorCode?, name: String): UiText =
        if (code == ErrorCode.SUBSCRIPTION_NOT_FOUND) uiText(R.string.home_failure_no_subscription) else uiText(R.string.subs_error_activate, name)
}
