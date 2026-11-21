package com.zephyr.app.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.em
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZButtonSize
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ImportSource
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import com.zephyr.engine.SceneSource
import com.zephyr.app.ui.common.resolve
import com.zephyr.app.ui.subs.ImportOptions
import com.zephyr.app.ui.subs.addedText
import com.zephyr.app.ui.subs.rememberSubscriptionImporter

/** Two-step onboarding (prototype ob1/ob2): add a subscription, then choose 简单 / 优选. */
@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    val c = ZTheme.colors
    var step by rememberSaveable { mutableIntStateOf(0) }
    var addedName by rememberSaveable { mutableStateOf("") }
    var addedNodes by rememberSaveable { mutableStateOf(0L) }
    var url by rememberSaveable { mutableStateOf("") }
    var showField by rememberSaveable { mutableStateOf(false) }
    var mode by rememberSaveable { mutableIntStateOf(1) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // Review L-P1-2: same import path as the sheet; failures are shown; the chosen mode is written before finishing.
    val imp = rememberSubscriptionImporter { r -> addedName = r.first.name; addedNodes = r.first.nodeCount; step = 1 }
    // Review L-P2-11: system back on step 2 returns to step 1 instead of leaving the app.
    androidx.activity.compose.BackHandler(enabled = step == 1) { step = 0 }
    val dir = com.zephyr.app.ui.common.startToEndSign()
    // `.ob h1`: 300 34/1.18, −0.03em.
    val h1 = ZTheme.type.title.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Light, fontSize = 34.sp, lineHeight = 40.sp, letterSpacing = (-0.03).em)
    Column(Modifier.fillMaxSize().background(c.bg).statusBarsPadding().navigationBarsPadding().padding(top = 24.dp)) {
        com.zephyr.app.ui.common.ZephyrLockup(Modifier.padding(horizontal = 22.dp)) // `.obmk`
        Spacer(Modifier.height(28.dp))
        ZText("${step + 1} / 2", Modifier.padding(horizontal = 22.dp), style = ZTheme.type.footnote, color = c.text3)
        AnimatedContent(step, transitionSpec = { (slideInHorizontally(ZAnim.slow()) { dir * it / 3 } + fadeIn(ZAnim.standard())) togetherWith (slideOutHorizontally(ZAnim.standard()) { -dir * it / 3 } + fadeOut(ZAnim.micro())) }, label = "ob") { s ->
            Column(Modifier.fillMaxWidth()) {
                if (s == 0) {
                    ZText(stringResource(R.string.subs_add), Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = h1)
                    if (showField) {
                        Column(Modifier.padding(horizontal = 16.dp)) {
                            ZSearchField(url, { url = it; imp.error = null }, stringResource(R.string.subs_paste_placeholder), onSubmit = { imp.submit(ImportSource.URL, url) })
                            Spacer(Modifier.height(12.dp))
                            ZButton(stringResource(if (imp.busy) R.string.common_adding else R.string.common_add), { imp.submit(ImportSource.URL, url) }, Modifier.fillMaxWidth(), enabled = url.isNotBlank() && !imp.busy)
                        }
                        Spacer(Modifier.height(16.dp))
                    }
                    ImportOptions(imp, clipboard = false, paste = if (showField) null else ({
                        // Prefill from the clipboard when it holds a link; otherwise open the field to paste by hand.
                        val t = imp.clipboardText().also { imp.error = null }
                        // Any §15 payload counts: a bare link, a desktop sync code or a clash:// link (the latter two ask to confirm).
                        if (t != null && runCatching { com.zephyr.engine.ImportPayloads.parse(t) }.isSuccess) { if (t.startsWith("http", ignoreCase = true)) url = t; imp.submit(ImportSource.CLIPBOARD, t) }
                        showField = true
                    }))
                    if (imp.busy) {
                        // iOS #99 parity: an import in flight can be abandoned without waiting.
                        androidx.compose.foundation.layout.Row(Modifier.padding(horizontal = 22.dp, vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            if (!showField) ZText(stringResource(R.string.common_adding), style = ZTheme.type.footnote, color = c.text2)
                            Spacer(Modifier.weight(1f))
                            ZText(stringResource(R.string.common_cancel), Modifier.zPressable(label = stringResource(R.string.onboarding_cancel_import_a11y)) { imp.cancel() }.padding(horizontal = 8.dp, vertical = 6.dp), style = ZTheme.type.footnote, color = c.accentText)
                        }
                    }
                    imp.error?.let { ZText(it.resolve(), Modifier.padding(horizontal = 22.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.danger) }
                    imp.hint?.let { ZText(it.resolve(), Modifier.padding(horizontal = 22.dp, vertical = 4.dp), style = ZTheme.type.footnote, color = c.text2) }
                    ZText(stringResource(R.string.common_local_data_note), Modifier.padding(22.dp), style = ZTheme.type.footnote, color = c.text3)
                } else {
                    ZText(addedText(addedName, addedNodes).resolve(), Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.callout, color = c.connected)
                    ZText(stringResource(R.string.onboarding_choose_mode), Modifier.padding(horizontal = 22.dp), style = h1)
                    Spacer(Modifier.height(16.dp))
                    Choice(stringResource(R.string.onboarding_simple), stringResource(R.string.onboarding_simple_desc), mode == 0) { mode = 0 }
                    Spacer(Modifier.height(12.dp))
                    Choice(stringResource(R.string.onboarding_optimized), stringResource(R.string.onboarding_optimized_desc), mode == 1) { mode = 1 }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        if (step == 1) {
            ZButton(stringResource(R.string.onboarding_continue), {
                if (!saving) scope.launch {
                    saving = true
                    applyOnboardingMode(simple = mode == 0)
                    AppGraph.settings.setOnboarded(); onDone()
                }
            }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), enabled = !saving, size = ZButtonSize.Large)
            ZText(stringResource(R.string.onboarding_change_later), Modifier.fillMaxWidth().padding(12.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3)
        }
    }
}

/**
 * 简单 = every scene follows the subscription's own group; 优选 = Zephyr picks from tested nodes.
 * Fresh install: no exit has been used yet, so switching AI here is not an exit change the user must confirm.
 */
private suspend fun applyOnboardingMode(simple: Boolean) {
    val engine = AppGraph.engine
    val source = if (simple) SceneSource.SUBSCRIPTION_GROUP else SceneSource.AUTO
    val scenes = runCatching { withTimeoutOrNull(2_000) { engine.scenes().first() } }.getOrNull().orEmpty()
    scenes.filter { it.source != source }.forEach { runCatching { engine.setSceneSource(it.id, source) } }
}

@Composable
private fun Choice(title: String, body: String, selected: Boolean, onClick: () -> Unit) {
    val c = ZTheme.colors
    // Review L-P2-11: prototype `.opt` — s1 fill, 7% accent when on, radio dot `.rd`, radio semantics.
    Row(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth()
            .background(if (selected) c.accent.copy(alpha = 0.07f) else c.surface1, ZTheme.shapes.card)
            .border(1.dp, if (selected) c.accent else c.hairline, ZTheme.shapes.card)
            .zPressable(haptic = !selected, role = androidx.compose.ui.semantics.Role.RadioButton, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(18.dp),
    ) {
        Box(
            Modifier.padding(top = 1.dp).size(22.dp)
                .border(if (selected) 7.dp else 1.5.dp, if (selected) c.accent else c.text4, androidx.compose.foundation.shape.CircleShape),
        )
        Spacer(Modifier.width(14.dp))
        Column {
            ZText(title, style = ZTheme.type.headline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium, fontSize = 17.sp))
            Spacer(Modifier.height(6.dp))
            ZText(body, style = ZTheme.type.callout, color = c.text2)
        }
    }
}
