package com.zephyr.app.ui.subs

import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.zephyr.app.di.AppGraph
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZDivider
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZListGroup
import com.zephyr.design.components.ZSearchField
import com.zephyr.design.components.ZSheet
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.ImportSource
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.launch

/** "添加订阅" (prototype ob1): paste link · scan QR · import from desktop Zephyr · file. */
@Composable
fun BoxScope.ImportSheet(visible: Boolean, onDismiss: () -> Unit, onDone: (String) -> Unit) {
    val ctx = LocalContext.current
    val c = ZTheme.colors
    val scope = rememberCoroutineScope()
    var url by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    fun submit(src: ImportSource, payload: String) = scope.launch {
        busy = true; error = null
        try { val s = AppGraph.engine.importSubscription(src, payload); url = ""; onDone("已添加 ${s.name}（${s.nodeCount} 个节点）") }
        catch (e: ZephyrException) { error = "这不是有效的订阅链接" }
        busy = false
    }
    ZSheet(visible, onDismiss, "添加订阅", trailing = "取消") {
        Column(Modifier.padding(horizontal = 16.dp)) {
            ZSearchField(url, { url = it; error = null }, "粘贴订阅链接", onSubmit = { submit(ImportSource.URL, url) })
            error?.let { ZText(it, Modifier.padding(start = 6.dp, top = 6.dp), style = ZTheme.type.footnote, color = c.danger) }
            Spacer(Modifier.height(12.dp))
            ZButton(if (busy) "正在添加…" else "添加", { submit(ImportSource.URL, url) }, Modifier.fillMaxWidth(), enabled = url.isNotBlank() && !busy)
        }
        Spacer(Modifier.height(16.dp))
        ZListGroup {
            Option(ZIcons.Link, "从剪贴板粘贴") {
                val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val t = cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString().orEmpty()
                if (t.isBlank()) error = "剪贴板是空的" else submit(ImportSource.CLIPBOARD, t)
            }
            ZDivider(); Option(ZIcons.Qr, "扫描二维码") { error = "相机扫码将在核心接入后启用" }
            ZDivider(); Option(ZIcons.Laptop, "从电脑上的 Zephyr 导入") { error = "在电脑端打开 设置 › 移动端，扫描二维码" }
            ZDivider(); Option(ZIcons.File, "从文件导入") { error = "请从文件管理器用 Zephyr 打开 .yaml 文件" }
        }
        ZText("订阅与流量数据仅保存在此设备上。", Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = ZTheme.type.footnote, color = c.text3)
    }
}

@Composable
private fun Option(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().zPressable(onClick = onClick).padding(horizontal = 20.dp, vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        ZIcon(icon, tint = ZTheme.colors.accent, size = 22.dp)
        Spacer(Modifier.width(14.dp))
        ZText(label, Modifier.weight(1f), style = ZTheme.type.body)
        ZIcon(ZIcons.ChevronRight, tint = ZTheme.colors.text4, size = 16.dp)
    }
}
