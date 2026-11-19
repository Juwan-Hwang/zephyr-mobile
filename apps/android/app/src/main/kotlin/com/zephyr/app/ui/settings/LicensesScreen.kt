package com.zephyr.app.ui.settings

import android.content.res.AssetManager
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.app.BuildConfig
import com.zephyr.app.R
import com.zephyr.app.ui.common.BackTo
import com.zephyr.app.ui.common.PageScaffold
import com.zephyr.design.components.ZSectionHeader
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Public source of the GPL-3.0 App (docs/release.md D1 / §6); each release's source is the `mobile-v<version>` tag. */
const val SOURCE_URL = "https://github.com/Juwan-Hwang/zephyr-mobile"
fun sourceTag(versionName: String = BuildConfig.VERSION_NAME) = "mobile-v$versionName"

/** assets/licenses/ is filled from the repo root at build time (app/build.gradle.kts `bundleLicenseAssets`). */
internal enum class LicenseDoc(val asset: String, val title: Int) {
    APP("licenses/LICENSE", R.string.licenses_section_app),
    NOTICES("licenses/THIRD_PARTY_NOTICES.md", R.string.licenses_section_notices),
    TEXTS("licenses/THIRD_PARTY_LICENSES.txt", R.string.licenses_section_texts),
}

/**
 * Splits a (large, ~700 KB) license file at blank lines into lazily rendered blocks; joining them with "\n\n" gives
 * the file back except for runs of blank lines, which collapse to one.
 */
internal fun licenseBlocks(text: String): List<String> =
    text.replace("\r\n", "\n").split(Regex("\n[ \t]*\n+")).map { it.trimEnd() }.filter { it.isNotBlank() }

private fun AssetManager.blocks(doc: LicenseDoc): List<String> =
    runCatching { open(doc.asset).bufferedReader().use { it.readText() } }.map(::licenseBlocks).getOrDefault(emptyList())

/** 设置 › 关于 › 开源许可: license statement + source location, then the notices and every license text, monospace. */
@Composable
fun LicensesScreen(onBack: () -> Unit) {
    val c = ZTheme.colors
    val assets = LocalContext.current.assets
    val docs by produceState<List<Pair<LicenseDoc, List<String>>>?>(null) {
        value = withContext(Dispatchers.IO) { LicenseDoc.entries.map { it to assets.blocks(it) } }
    }
    PageScaffold(BackTo.SETTINGS, stringResource(R.string.settings_licenses), onBack) {
        LazyColumn(Modifier.fillMaxSize().navigationBarsPadding()) {
            item("intro") {
                ZText(
                    stringResource(R.string.licenses_intro, SOURCE_URL, sourceTag()),
                    Modifier.padding(horizontal = 22.dp, vertical = 8.dp), style = ZTheme.type.footnote, color = c.text2,
                )
            }
            val loaded = docs ?: return@LazyColumn
            if (loaded.all { it.second.isEmpty() }) {
                item("none") {
                    Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                        ZText(stringResource(R.string.licenses_unavailable), style = ZTheme.type.body, color = c.text3)
                    }
                }
            }
            loaded.forEach { (doc, blocks) ->
                if (blocks.isEmpty()) return@forEach
                item("h-${doc.name}") {
                    ZSectionHeader(stringResource(doc.title), Modifier.padding(top = 16.dp).semantics { heading() })
                }
                // License texts are English/ASCII art: keep them left-to-right even in RTL locales.
                items(blocks.size, key = { "${doc.name}-$it" }) { i ->
                    androidx.compose.runtime.CompositionLocalProvider(
                        androidx.compose.ui.platform.LocalLayoutDirection provides androidx.compose.ui.unit.LayoutDirection.Ltr,
                    ) {
                        ZText(blocks[i], Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), style = ZTheme.type.monoSmall, color = c.text1)
                    }
                }
            }
        }
    }
}
