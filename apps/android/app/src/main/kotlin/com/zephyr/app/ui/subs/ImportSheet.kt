package com.zephyr.app.ui.subs

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.zephyr.app.R
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.resolve
import com.zephyr.app.ui.common.toPluralCount
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ImportPayloadKind
import com.zephyr.engine.ImportSource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics

/**
 * "添加订阅" (prototype ob1): paste link · clipboard · scan QR · import from desktop Zephyr · file.
 * [deepLink] is a clash:// / clashmeta:// / mihomo:// / zephyr:// link opened from another app: it is parsed and
 * listed for confirmation, never imported silently (review A-P1-4, audit U26).
 */
@Composable
fun BoxScope.ImportSheet(visible: Boolean, onDismiss: () -> Unit, deepLink: String? = null, onDone: (UiText) -> Unit) {
    val c = ZTheme.colors
    var url by remember { mutableStateOf("") }
    val imp = rememberSubscriptionImporter { r -> url = ""; onDone(importedText(r)) }
    androidx.compose.runtime.LaunchedEffect(deepLink) { if (deepLink != null) imp.offer(deepLink) }
    // iOS #99 parity: 取消 and a swipe-down both abandon an import in flight.
    ZSheet(visible, { imp.cancel(); onDismiss() }, stringResource(R.string.subs_add), trailing = stringResource(R.string.common_cancel)) {
        if (imp.pending == null) {
            Column(Modifier.padding(horizontal = 16.dp)) {
                ZSearchField(url, { url = it; imp.error = null }, stringResource(R.string.subs_paste_placeholder), onSubmit = { imp.submit(ImportSource.URL, url) })
                imp.error?.let { ZText(it.resolve(), Modifier.padding(start = 6.dp, top = 6.dp), style = ZTheme.type.footnote, color = c.dangerText) }
                Spacer(Modifier.height(12.dp))
                ZButton(stringResource(if (imp.busy) R.string.common_adding else R.string.common_add), { imp.submit(ImportSource.URL, url) }, Modifier.fillMaxWidth(), enabled = url.isNotBlank() && !imp.busy)
            }
            Spacer(Modifier.height(16.dp))
        }
        ImportOptions(imp, clipboard = true)
        imp.hint?.let { ZText(it.resolve(), Modifier.padding(horizontal = 22.dp, vertical = 4.dp), style = ZTheme.type.footnote, color = c.text2) }
        ZText(stringResource(R.string.common_local_data_note), Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3)
    }
}

/**
 * The import rows shared with onboarding. [clipboard] adds "从剪贴板粘贴" (onboarding has its own paste row).
 * While items wait for confirmation (several at once, or a link from another app) the rows give way to that list;
 * the camera scanner is hosted here too, so both callers get it.
 */
@Composable
fun ImportOptions(imp: SubscriptionImporter, clipboard: Boolean, paste: (() -> Unit)? = null) {
    imp.scanning?.let { desktop -> QrScanDialog(desktop, onCode = { imp.onScanned(it) }, onClose = { imp.onScanned(null) }) }
    val pending = imp.pending
    if (pending != null) { PendingImportPanel(pending, onConfirm = { imp.confirm() }, onCancel = { imp.dismissPending() }); return }
    ZListGroup {
        if (paste != null) { Option(ZIcons.Link, stringResource(R.string.subs_paste_link), onClick = paste); ZDivider() }
        if (clipboard) { Option(ZIcons.Link, stringResource(R.string.subs_paste_clipboard)) { imp.pasteClipboard() }; ZDivider() }
        Option(ZIcons.Qr, stringResource(R.string.subs_scan_qr)) { imp.scan(desktop = false) }
        ZDivider(); Option(ZIcons.Laptop, stringResource(R.string.subs_import_desktop)) { imp.scan(desktop = true) }
        ZDivider(); Option(ZIcons.File, stringResource(R.string.subs_import_file)) { imp.pickFile() }
    }
}

/** Contract §15 "多条时列出确认" + audit U26 (source, http warning, trust note for links from other apps). */
@Composable
private fun PendingImportPanel(p: PendingImport, onConfirm: () -> Unit, onCancel: () -> Unit) {
    val c = ZTheme.colors
    val n = p.payload.items.size
    Column(Modifier.padding(horizontal = 16.dp)) {
        ZText(pluralStringResource(R.plurals.subs_import_confirm_title, n, n), Modifier.padding(horizontal = 6.dp).semantics { heading() }, style = ZTheme.type.headline)
        Spacer(Modifier.height(12.dp))
        ZListGroup {
            p.payload.items.forEachIndexed { i, it ->
                if (i > 0) ZDivider()
                val host = hostOf(it.url)
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)) {
                    ZText(it.name ?: host, style = ZTheme.type.body, maxLines = 1)
                    if (it.name != null) ZText(host, style = ZTheme.type.footnote, color = c.text3, maxLines = 1)
                }
            }
        }
        if (p.external) {
            val source = if (p.payload.kind == ImportPayloadKind.ZEPHYR && n > 1) stringResource(R.string.subs_import_desktop_source)
                else p.payload.items.map { hostOf(it.url) }.distinct().joinToString(", ")
            Spacer(Modifier.height(10.dp))
            ZText(stringResource(R.string.subs_import_source, source), Modifier.padding(horizontal = 6.dp), style = ZTheme.type.footnote, color = c.text2)
            if (p.insecure) ZText(stringResource(R.string.subs_import_insecure), Modifier.padding(horizontal = 6.dp, vertical = 4.dp), style = ZTheme.type.footnote, color = c.warningText)
            ZText(stringResource(R.string.subs_import_trust), Modifier.padding(horizontal = 6.dp), style = ZTheme.type.footnote, color = c.text3)
        } else if (p.insecure) {
            Spacer(Modifier.height(10.dp))
            ZText(stringResource(R.string.subs_import_insecure), Modifier.padding(horizontal = 6.dp), style = ZTheme.type.footnote, color = c.warningText)
        }
        Spacer(Modifier.height(16.dp))
        ZButton(stringResource(R.string.common_add), onConfirm, Modifier.fillMaxWidth())
        Spacer(Modifier.height(8.dp))
        ZButton(stringResource(R.string.common_cancel), onCancel, Modifier.fillMaxWidth(), kind = com.zephyr.design.components.ZButtonKind.Ghost)
    }
}

/** Host only: the import code's full link carries the provider token and is never shown. */
private fun hostOf(url: String): String = runCatching { java.net.URI(url).host }.getOrNull()
    ?: url.substringAfter("://").substringBefore('/').substringBefore('?').substringAfterLast('@')

/** "Added Orbit (512 nodes)" — the toast after an import, also the onboarding confirmation. */
fun addedText(name: String, nodes: Long): UiText = UiText.Plural(R.plurals.subs_added, nodes.toPluralCount(), listOf(name, ZFormat.grouped(nodes)))

/** One subscription: "Added Orbit (512 nodes)"; several: "Added 3 subscriptions", plus how many failed. */
fun importedText(r: ImportResult): UiText {
    val main = if (r.subs.size == 1) addedText(r.first.name, r.first.nodeCount)
        else UiText.Plural(R.plurals.subs_added_many, r.subs.size)
    if (r.failed == 0) return main
    return UiText.Res(R.string.common_joined_dot, listOf(main, UiText.Plural(R.plurals.subs_import_some_failed, r.failed)))
}

@Composable
private fun Option(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean = true, note: String? = null, onClick: () -> Unit) {
    val c = ZTheme.colors
    Row(Modifier.fillMaxWidth().then(if (enabled) Modifier.zPressable(onClick = onClick) else Modifier).padding(horizontal = 20.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        ZIcon(icon, tint = if (enabled) c.accent else c.text4, size = 22.dp)
        Spacer(Modifier.width(14.dp))
        ZText(label, Modifier.weight(1f), style = ZTheme.type.body, color = if (enabled) c.text1 else c.text3)
        note?.let { ZText(it, style = ZTheme.type.footnote, color = c.text4) }
        ZIcon(ZIcons.ChevronRight, tint = ZTheme.colors.text4, size = 16.dp)
    }
}
