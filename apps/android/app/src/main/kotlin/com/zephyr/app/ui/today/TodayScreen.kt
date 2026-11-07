package com.zephyr.app.ui.today

import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.provider.MediaStore
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.zephyr.app.di.AppGraph
import com.zephyr.app.ui.common.ZephyrLockup
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZButtonKind
import com.zephyr.design.components.ZIconButton
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.format.ZFormat
import com.zephyr.design.theme.ZAnim
import com.zephyr.design.theme.ZTheme
import com.zephyr.engine.UsageSummary
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin

enum class TodayStyle(val label: String, val bg: Color, val line: Color, val fg: Color) {
    Night("夜", Color(0xFF05060A), Color(0xFF3BA4FF), Color.White),
    Dawn("晨", Color(0xFFF1ECE6), Color(0xFFE07A4F), Color(0xFF1B1B1F)),
    Mist("雾", Color(0xFFE6ECF4), Color(0xFF6C8DB8), Color(0xFF1B1B1F)),
}

/** "今日" share card (prototype `today`): flow-field art generated from today's hourly traffic — no node names, no IPs. */
@Composable
fun TodayScreen(onClose: () -> Unit) {
    val usage by produceState<UsageSummary?>(null) { value = AppGraph.engine.usageToday() }
    var style by remember { mutableStateOf(TodayStyle.Night) }
    val layer = rememberGraphicsLayer()
    val scope = rememberCoroutineScope()
    val ctx = LocalContext.current
    val c = ZTheme.colors
    Column(Modifier.fillMaxSize().background(c.bg).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp)) { Spacer(Modifier.weight(1f)); ZIconButton(ZIcons.Close, "关闭", onClose, tint = c.text2) }
        val u = usage
        Box(
            Modifier.padding(horizontal = 22.dp).fillMaxWidth().aspectRatio(0.68f)
                .drawWithContent { layer.record { this@drawWithContent.drawContent() }; drawLayer(layer) }
                .clip(ZTheme.shapes.card).background(style.bg).border(1.dp, c.hairline, ZTheme.shapes.card),
        ) {
            if (u != null) Flow(u.hourly, style)
            Column(Modifier.align(Alignment.BottomStart).padding(24.dp)) {
                val date = LocalDate.now().format(DateTimeFormatter.ofPattern("M月d日 · EEEE", Locale.CHINA))
                ZText(date, style = ZTheme.type.footnote, color = style.fg.copy(alpha = 0.6f))
                val (v, unit) = ZFormat.bytes(u?.todayBytes ?: 0)
                Row(verticalAlignment = Alignment.Bottom) {
                    ZText(v, style = ZTheme.type.display, color = style.fg)
                    Spacer(Modifier.width(8.dp))
                    ZText(unit, Modifier.padding(bottom = 14.dp), style = ZTheme.type.title.copy(fontWeight = ZTheme.type.body.fontWeight), color = style.fg.copy(alpha = 0.6f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(36.dp)) {
                    Stat("${u?.regionsToday ?: 0}", "个地区", style.fg)
                    Stat("${(u?.onlineMillisToday ?: 0) / 3_600_000}", "小时在线", style.fg)
                    Stat("${u?.fastestLatencyMs ?: "—"}", "ms 最快", style.fg)
                }
                Spacer(Modifier.height(18.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(style.fg.copy(alpha = 0.14f)))
                Spacer(Modifier.height(14.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ZephyrLockup(tint = style.fg)
                    Spacer(Modifier.weight(1f))
                    ZText("今日", style = ZTheme.type.footnote, color = style.fg.copy(alpha = 0.5f))
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TodayStyle.entries.forEach { s ->
                val border by animateColorAsState(if (s == style) c.text2 else c.hairlineStrong, ZAnim.standard(), label = "b")
                Row(
                    Modifier.clip(ZTheme.shapes.pill).border(1.dp, border, ZTheme.shapes.pill).zPressable(haptic = true) { style = s }.padding(start = 6.dp, end = 16.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(28.dp).clip(CircleShape).background(s.bg).border(1.dp, c.hairlineStrong, CircleShape))
                    Spacer(Modifier.width(10.dp))
                    ZText(s.label, style = ZTheme.type.callout)
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        Row(Modifier.padding(horizontal = 22.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ZButton("分享", { scope.launch { val b = layer.toImageBitmap().asAndroidBitmap(); share(ctx, b) } }, Modifier.weight(1f))
            ZButton("存储图像", { scope.launch { save(ctx, layer.toImageBitmap().asAndroidBitmap()) } }, Modifier.weight(1f), kind = ZButtonKind.Secondary)
        }
        ZText("图案由今天的流量生成，不含节点名称与 IP 地址。", Modifier.fillMaxWidth().padding(16.dp), style = ZTheme.type.footnote.copy(textAlign = androidx.compose.ui.text.style.TextAlign.Center), color = c.text3)
    }
}

@Composable
private fun Stat(v: String, label: String, fg: Color) {
    Column {
        ZText(v, style = ZTheme.type.number, color = fg)
        ZText(label, style = ZTheme.type.footnote, color = fg.copy(alpha = 0.55f))
    }
}

/** ~140 flowing strands whose amplitude follows the 24 hourly volumes. Deterministic per day. */
@Composable
private fun Flow(hourly: List<Long>, style: TodayStyle) {
    val max = (hourly.maxOrNull() ?: 1L).coerceAtLeast(1L).toFloat()
    Canvas(Modifier.fillMaxSize()) {
        val w = size.width; val h = size.height
        val strands = 140
        for (s in 0 until strands) {
            val p = Path()
            val t = s / strands.toFloat()
            val baseY = h * (0.12f + 0.55f * t)
            var x = 0f
            p.moveTo(0f, baseY)
            while (x <= w) {
                val hour = ((x / w) * 23).toInt().coerceIn(0, 23)
                val amp = (hourly.getOrNull(hour) ?: 0L) / max
                val y = baseY - sin((x / w) * PI * 1.1 + t * 2.4).toFloat() * h * 0.18f * (0.4f + amp) + t * x * 0.12f
                p.lineTo(x, y)
                x += 6f
            }
            val a = 0.05f + 0.35f * (1f - kotlin.math.abs(t - 0.45f) * 2f).coerceAtLeast(0f)
            drawPath(p, style.line.copy(alpha = a), style = Stroke(width = 1.1f))
        }
        drawCircle(style.line.copy(alpha = 0.0f), 1f, Offset.Zero)
    }
}

// PNG encode of a ~1000×1500 bitmap is 100–300 ms: never on the main thread (review H-P1-10).
private suspend fun share(ctx: android.content.Context, bmp: Bitmap) {
    val f = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        val dir = java.io.File(ctx.cacheDir, "share").apply { mkdirs() }
        java.io.File(dir, "zephyr-today.png").also { f -> f.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) } }
    }
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", f)
    ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), null))
}

private suspend fun save(ctx: android.content.Context, bmp: Bitmap) = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "Zephyr-${System.currentTimeMillis()}.png")
        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
        if (Build.VERSION.SDK_INT >= 29) put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Zephyr")
    }
    ctx.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)?.let { uri ->
        ctx.contentResolver.openOutputStream(uri)?.use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
