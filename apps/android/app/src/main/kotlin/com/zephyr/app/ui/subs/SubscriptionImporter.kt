package com.zephyr.app.ui.subs

import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.zephyr.app.di.AppGraph
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ImportSource
import com.zephyr.engine.Subscription
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * One import implementation shared by the import sheet and onboarding (review L-P1-2/L-P1-3):
 * link, clipboard, file (SAF, ≤ 32 MB). Errors are shown, never swallowed.
 */
@Stable
class SubscriptionImporter internal constructor(
    private val scope: CoroutineScope,
    private val ctx: Context,
    private val done: () -> (Subscription) -> Unit,
) {
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null)
    var hint by mutableStateOf<String?>(null)
    internal var launchPicker: () -> Unit = {}

    fun submit(src: ImportSource, payload: String) {
        if (busy) return
        scope.launch {
            busy = true; error = null
            try { done()(AppGraph.engine.importSubscription(src, payload)) }
            catch (e: ZephyrException) { error = message(src, e) }
            finally { busy = false }
        }
    }

    /** Clipboard text, or null (and an error) when empty. */
    fun clipboardText(): String? {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val t = cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString()?.trim().orEmpty()
        if (t.isEmpty()) error = "剪贴板是空的"
        return t.ifEmpty { null }
    }

    fun pasteClipboard() { clipboardText()?.let { submit(ImportSource.CLIPBOARD, it) } }

    fun pickFile() { error = null; hint = null; launchPicker() }

    fun showDesktopHint() { error = null; hint = "在电脑端打开 设置 › 移动端，即可显示二维码" }

    internal fun onFile(text: String?) {
        if (text.isNullOrBlank()) error = "无法读取这个文件" else submit(ImportSource.FILE, text)
    }

    private fun message(src: ImportSource, e: ZephyrException): String = when (e.error.code) {
        ErrorCode.SUBSCRIPTION_FETCH_FAILED -> "无法下载这个订阅，请检查链接或网络"
        else -> if (src == ImportSource.FILE) "这不是有效的配置文件" else "这不是有效的订阅链接"
    }

    companion object {
        const val MAX_BYTES = 32 * 1024 * 1024
        val MIME = arrayOf("application/x-yaml", "application/yaml", "text/*", "application/octet-stream")
    }
}

@Composable
fun rememberSubscriptionImporter(onDone: (Subscription) -> Unit): SubscriptionImporter {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val latest by rememberUpdatedState(onDone)
    val imp = remember { SubscriptionImporter(scope, ctx) { latest } }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val text = withContext(Dispatchers.IO) {
                runCatching {
                    ctx.contentResolver.openInputStream(uri)?.use { ins ->
                        val out = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(64 * 1024)
                        while (true) {
                            val n = ins.read(chunk); if (n < 0) break
                            out.write(chunk, 0, n)
                            if (out.size() > SubscriptionImporter.MAX_BYTES) return@use null
                        }
                        out.toString(Charsets.UTF_8.name())
                    }
                }.getOrNull()
            }
            imp.onFile(text)
        }
    }
    imp.launchPicker = { picker.launch(SubscriptionImporter.MIME) }
    return imp
}
