package com.zephyr.app.ui.subs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.app.R
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZButtonKind
import com.zephyr.design.components.ZCard
import com.zephyr.design.components.ZText
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.Subscription
import com.zephyr.engine.SubscriptionDiff
import com.zephyr.engine.ZephyrEngine
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * "更新前显示更改" (audit U2, iOS SubscriptionsModel.reviewFirst): with the setting on, an update first runs
 * `previewUpdate` and shows the diff; nothing changes until the user taps 更新.
 */
@Immutable
sealed interface UpdateReview {
    val diff: SubscriptionDiff
    data class One(val sub: Subscription, override val diff: SubscriptionDiff) : UpdateReview
    data class All(val count: Int, override val diff: SubscriptionDiff) : UpdateReview
}

/**
 * Previews every subscription (6 at a time, like iOS) and sums the diffs. Local profiles and failures are skipped;
 * null when none could be previewed.
 */
internal suspend fun previewAll(engine: ZephyrEngine): UpdateReview.All? = coroutineScope {
    val subs = engine.subscriptions().first()
    val gate = Semaphore(6)
    val diffs = subs.map { s -> async { gate.withPermit { runCatching { engine.previewUpdate(s.id) }.getOrNull() } } }.mapNotNull { it.await() }
    if (diffs.isEmpty()) null
    else UpdateReview.All(
        diffs.size,
        SubscriptionDiff(
            addedNodes = diffs.sumOf { it.addedNodes }, removedNodes = diffs.sumOf { it.removedNodes }, ruleChanges = diffs.sumOf { it.ruleChanges },
            overridesKept = diffs.all { it.overridesKept }, scenesRetested = diffs.any { it.scenesRetested },
        ),
    )
}

@Composable
internal fun SubscriptionReviewCard(review: UpdateReview, onConfirm: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val c = ZTheme.colors
    val d = review.diff
    ZCard(modifier.semantics { liveRegion = LiveRegionMode.Polite }, padding = 18.dp) {
        val title = when (review) {
            is UpdateReview.One -> stringResource(R.string.subs_review_one, review.sub.name)
            is UpdateReview.All -> pluralStringResource(R.plurals.subs_review_all, review.count, ZFormat.grouped(review.count.toLong()))
        }
        ZText(title, Modifier.semantics { heading() }, style = ZTheme.type.headline.copy(fontWeight = ZTheme.type.body.fontWeight))
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(28.dp)) {
            ReviewDelta("+" + ZFormat.grouped(d.addedNodes), stringResource(R.string.common_nodes), c.connected)
            ReviewDelta("−" + ZFormat.grouped(d.removedNodes), stringResource(R.string.common_nodes), c.danger)
            ReviewDelta(ZFormat.grouped(d.ruleChanges), stringResource(R.string.subs_rule_changes), c.text1)
        }
        Spacer(Modifier.height(12.dp))
        ZText(stringResource(R.string.subs_review_note), style = ZTheme.type.footnote, color = c.text3)
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.End, modifier = Modifier.padding(top = 2.dp)) {
            Spacer(Modifier.weight(1f))
            ZButton(stringResource(R.string.common_cancel), onCancel, kind = ZButtonKind.Ghost)
            Spacer(Modifier.width(8.dp))
            ZButton(stringResource(R.string.subs_swipe_update), onConfirm)
        }
    }
}

@Composable
private fun ReviewDelta(v: String, label: String, color: androidx.compose.ui.graphics.Color) {
    Column {
        ZText(v, style = ZTheme.type.number.copy(fontSize = 22.sp, fontWeight = FontWeight.Light, lineHeight = 26.sp), color = color)
        ZText(label, style = ZTheme.type.footnote, color = ZTheme.colors.text3)
    }
}
