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
import com.zephyr.engine.ImportSource

/** "添加订阅" (prototype ob1): paste link · scan QR · import from desktop Zephyr · file. */
@Composable
fun BoxScope.ImportSheet(visible: Boolean, onDismiss: () -> Unit, prefill: String? = null, onDone: (UiText) -> Unit) {
    val c = ZTheme.colors
    var url by remember { mutableStateOf("") }
    val imp = rememberSubscriptionImporter { s -> url = ""; onDone(addedText(s.name, s.nodeCount)) }
    // Deep links land here pre-filled and wait for 添加 (review A-P1-4).
    androidx.compose.runtime.LaunchedEffect(prefill) { if (prefill != null) { url = prefill; imp.error = null } }
    // iOS #99 parity: 取消 and a swipe-down both abandon an import in flight.
    ZSheet(visible, { imp.cancel(); onDismiss() }, stringResource(R.string.subs_add), trailing = stringResource(R.string.common_cancel)) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            ZSearchField(url, { url = it; imp.error = null }, stringResource(R.string.subs_paste_placeholder), onSubmit = { imp.submit(ImportSource.URL, url) })
            imp.error?.let { ZText(it.resolve(), Modifier.padding(start = 6.dp, top = 6.dp), style = ZTheme.type.footnote, color = c.danger) }
            Spacer(Modifier.height(12.dp))
            ZButton(stringResource(if (imp.busy) R.string.common_adding else R.string.common_add), { imp.submit(ImportSource.URL, url) }, Modifier.fillMaxWidth(), enabled = url.isNotBlank() && !imp.busy)
        }
        Spacer(Modifier.height(16.dp))
        ImportOptions(imp, clipboard = true)
        imp.hint?.let { ZText(it.resolve(), Modifier.padding(horizontal = 22.dp, vertical = 4.dp), style = ZTheme.type.footnote, color = c.text2) }
        ZText(stringResource(R.string.common_local_data_note), Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3)
    }
}

/** The import rows shared with onboarding. [clipboard] adds "从剪贴板粘贴" (onboarding has its own paste row). */
@Composable
fun ImportOptions(imp: SubscriptionImporter, clipboard: Boolean, paste: (() -> Unit)? = null) {
    ZListGroup {
        if (paste != null) { Option(ZIcons.Link, stringResource(R.string.subs_paste_link), onClick = paste); ZDivider() }
        if (clipboard) { Option(ZIcons.Link, stringResource(R.string.subs_paste_clipboard)) { imp.pasteClipboard() }; ZDivider() }
        Option(ZIcons.Qr, stringResource(R.string.subs_scan_qr), enabled = false, note = stringResource(R.string.subs_coming_soon)) {}
        ZDivider(); Option(ZIcons.Laptop, stringResource(R.string.subs_import_desktop)) { imp.showDesktopHint() }
        ZDivider(); Option(ZIcons.File, stringResource(R.string.subs_import_file)) { imp.pickFile() }
    }
}

/** "Added Orbit (512 nodes)" — the toast after an import, also the onboarding confirmation. */
fun addedText(name: String, nodes: Long): UiText = UiText.Plural(R.plurals.subs_added, nodes.toPluralCount(), listOf(name, ZFormat.grouped(nodes)))

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
