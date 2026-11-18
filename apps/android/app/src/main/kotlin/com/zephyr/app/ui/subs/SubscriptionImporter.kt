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
import com.zephyr.app.R
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.UiText
import com.zephyr.app.ui.common.uiText
import com.zephyr.engine.ErrorCode
import com.zephyr.engine.ImportItem
import com.zephyr.engine.ImportPayload
import com.zephyr.engine.ImportPayloadException
import com.zephyr.engine.ImportPayloadKind
import com.zephyr.engine.ImportPayloads
import com.zephyr.engine.ImportSource
import com.zephyr.engine.Subscription
import com.zephyr.engine.ZephyrException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What one import produced: the subscriptions added (in payload order) and how many items failed. */
data class ImportResult(val subs: List<Subscription>, val failed: Int = 0) {
    val first: Subscription get() = subs.first()
}

/**
 * Items waiting for the user's "添加" (contract §15: several at once are listed first; a link opened from another app
 * is never imported silently, audit U26). [external] = it came from a deep link, so the source is shown with a trust
 * note (and an http warning when a link is not encrypted).
 */
data class PendingImport(val source: ImportSource, val payload: ImportPayload, val external: Boolean) {
    val insecure: Boolean get() = payload.items.any { it.url.startsWith("http://", ignoreCase = true) }
}

/**
 * One import implementation shared by the import sheet and onboarding (review L-P1-2/L-P1-3):
 * link, clipboard, QR (camera), desktop sync code, deep link and file (SAF, ≤ 32 MB). Errors are shown, never
 * swallowed, and never as engine text (contract §0.5).
 */
@Stable
class SubscriptionImporter internal constructor(
    private val scope: CoroutineScope,
    private val ctx: Context?,
    private val done: () -> (ImportResult) -> Unit,
    private val engine: () -> com.zephyr.engine.ZephyrEngine = { AppGraph.engine },
) {
    var busy by mutableStateOf(false); private set
    var error by mutableStateOf<UiText?>(null)
    var hint by mutableStateOf<UiText?>(null)
    var pending by mutableStateOf<PendingImport?>(null); private set
    /** Camera scanner request: null = closed, true = "从电脑导入" wording, false = plain scan. */
    var scanning by mutableStateOf<Boolean?>(null); private set
    internal var launchPicker: () -> Unit = {}

    /** Bumped by [cancel]; a result from an older generation is late and is dropped (iOS #99 parity). */
    private var generation = 0

    /**
     * Text the user entered, pasted or scanned. A bare link imports at once; a desktop sync code / clash:// link /
     * several subscriptions are listed for confirmation first; a whole config pasted from the clipboard and files
     * are local profiles.
     */
    fun submit(src: ImportSource, payload: String) {
        if (busy) return
        error = null; hint = null
        val p = payload.trim()
        if (src == ImportSource.FILE || (src == ImportSource.CLIPBOARD && ImportPayloads.looksLikeConfig(p))) {
            run(src) { e -> ImportResult(listOf(e.importSubscription(src, p))) }
            return
        }
        val parsed = parse(src, p) ?: return
        if (parsed.kind == ImportPayloadKind.URL && parsed.items.size == 1) importItems(src, parsed.items)
        else pending = PendingImport(src, parsed, external = false)
    }

    /** A clash:// / clashmeta:// / mihomo:// / zephyr:// link opened from another app: always confirmed first (U26). */
    fun offer(payload: String) {
        if (busy) return
        error = null; hint = null; pending = null
        val parsed = parse(ImportSource.URL, payload.trim()) ?: return
        pending = PendingImport(ImportSource.URL, parsed, external = true)
    }

    /** "添加" on the confirmation: fetch and import every listed item. */
    fun confirm() {
        val p = pending ?: return
        if (busy) return
        pending = null
        importItems(p.source, p.payload.items)
    }

    fun dismissPending() { pending = null }

    private fun parse(src: ImportSource, p: String): ImportPayload? = try {
        engine().parseImportPayload(p)
    } catch (x: ImportPayloadException) {
        error = when {
            x.versionTooNew -> uiText(R.string.subs_error_import_version)
            else -> uiText(if (src == ImportSource.FILE) R.string.subs_error_invalid_file else R.string.subs_error_invalid_link)
        }
        null
    }

    private fun importItems(src: ImportSource, items: List<ImportItem>) = run(src) { e ->
        val ok = ArrayList<Subscription>(items.size)
        var lastError: ZephyrException? = null
        for (it in items) {
            try { ok += e.importItem(src, it) } catch (x: ZephyrException) { lastError = x }
        }
        if (ok.isEmpty()) throw lastError ?: ZephyrException(ErrorCode.SUBSCRIPTION_INVALID, "nothing imported")
        ImportResult(ok, failed = items.size - ok.size)
    }

    private fun run(src: ImportSource, block: suspend (com.zephyr.engine.ZephyrEngine) -> ImportResult) {
        if (busy) return
        val gen = ++generation
        busy = true; error = null
        scope.launch {
            val e = engine()
            // Ids that existed before: a cancelled import never removes one of these (re-adding a known link).
            val before = runCatching { e.subscriptions().first().map { it.id }.toSet() }.getOrDefault(emptySet())
            try {
                val r = block(e)
                if (gen != generation) r.subs.filter { it.id !in before }.forEach { runCatching { e.deleteSubscription(it.id) } }
                else done()(r)
            } catch (x: ZephyrException) {
                if (gen == generation) error = message(src, x)
            } finally {
                if (gen == generation) busy = false
            }
        }
    }

    /**
     * Abandon the running import: the sheet's 取消, a swipe-down, or onboarding's 取消. The UI is idle at once;
     * if the engine still finishes, a subscription it newly created is withdrawn.
     */
    fun cancel() {
        pending = null
        if (!busy) return
        generation++
        busy = false
    }

    /** Clipboard text, or null (and an error) when empty. */
    fun clipboardText(): String? {
        val cm = ctx?.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val t = cm?.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString()?.trim().orEmpty()
        if (t.isEmpty()) error = uiText(R.string.subs_error_clipboard_empty)
        return t.ifEmpty { null }
    }

    fun pasteClipboard() { clipboardText()?.let { submit(ImportSource.CLIPBOARD, it) } }

    fun pickFile() { error = null; hint = null; launchPicker() }

    /** "扫描二维码" / "从电脑上的 Zephyr 导入": both open the camera; [desktop] only changes the wording. */
    fun scan(desktop: Boolean) { error = null; hint = null; scanning = desktop }

    internal fun onScanned(code: String?) {
        scanning = null
        if (code != null) submit(ImportSource.QR, code)
    }

    internal fun onScanUnavailable(reason: UiText) { scanning = null; error = reason }

    internal fun onFile(text: String?) {
        if (text.isNullOrBlank()) error = uiText(R.string.subs_error_read_file) else submit(ImportSource.FILE, text)
    }

    private fun message(src: ImportSource, e: ZephyrException): UiText = when (e.error.code) {
        ErrorCode.SUBSCRIPTION_FETCH_FAILED -> uiText(R.string.subs_error_fetch)
        else -> uiText(if (src == ImportSource.FILE) R.string.subs_error_invalid_file else R.string.subs_error_invalid_link)
    }

    companion object {
        const val MAX_BYTES = 32 * 1024 * 1024
        val MIME = arrayOf("application/x-yaml", "application/yaml", "text/*", "application/octet-stream")
    }
}

@Composable
fun rememberSubscriptionImporter(onDone: (ImportResult) -> Unit): SubscriptionImporter {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val latest by rememberUpdatedState(onDone)
    val imp = remember { SubscriptionImporter(scope, ctx, done = { latest }) }
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
