package com.zephyr.app.ui.subs

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.zephyr.app.R
import com.zephyr.design.components.ZButton
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full-screen QR scanner for "扫描二维码" and "从电脑上的 Zephyr 导入" (audit U5; iOS QRScanSheet parity):
 * viewfinder + hint, camera permission asked here (never at launch), denied / no-camera states with a way out.
 * Hands the first decoded text to [onCode]; parsing (contract §15) happens in [SubscriptionImporter].
 */
@Composable
internal fun QrScanDialog(desktop: Boolean, onCode: (String) -> Unit, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val ctx = LocalContext.current
        val hasCamera = remember { ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
        var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
        var denied by remember { mutableStateOf(false) }
        val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> granted = ok; denied = !ok }
        LaunchedEffect(Unit) { if (hasCamera && !granted) ask.launch(Manifest.permission.CAMERA) }
        val title = stringResource(if (desktop) R.string.subs_import_desktop else R.string.subs_scan_qr)
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (hasCamera && granted) {
                CameraQrPreview(onCode, Modifier.fillMaxSize())
                Box(Modifier.align(Alignment.Center).size(240.dp).border(2.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(20.dp)))
            } else if (!hasCamera || denied) {
                Column(Modifier.align(Alignment.Center).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    ZText(
                        stringResource(if (hasCamera) R.string.subs_scan_camera_needed else R.string.subs_scan_no_camera),
                        style = ZTheme.type.headline.copy(textAlign = TextAlign.Center), color = Color.White,
                    )
                    if (hasCamera) {
                        Spacer(Modifier.height(16.dp))
                        ZButton(stringResource(R.string.common_open_settings), {
                            ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", ctx.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        })
                    }
                }
            }
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                ZText(
                    stringResource(R.string.common_cancel),
                    Modifier.zPressable(onClick = onClose).padding(horizontal = 12.dp, vertical = 10.dp),
                    style = ZTheme.type.body, color = Color.White,
                )
                ZText(title, Modifier.weight(1f).semantics { heading() }, style = ZTheme.type.headline.copy(textAlign = TextAlign.Center), color = Color.White)
                Spacer(Modifier.size(width = 72.dp, height = 1.dp))
            }
            ZText(
                stringResource(if (desktop) R.string.subs_hint_desktop else R.string.subs_scan_prompt),
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(24.dp),
                style = ZTheme.type.footnote.copy(textAlign = TextAlign.Center), color = Color.White.copy(alpha = 0.75f),
            )
        }
    }
}

@Composable
private fun CameraQrPreview(onCode: (String) -> Unit, modifier: Modifier) {
    val ctx = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val latest by rememberUpdatedState(onCode)
    val view = remember { PreviewView(ctx).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    DisposableEffect(owner) {
        val executor = Executors.newSingleThreadExecutor()
        val delivered = AtomicBoolean(false)
        val future = ProcessCameraProvider.getInstance(ctx)
        var provider: ProcessCameraProvider? = null
        future.addListener({
            val p = runCatching { future.get() }.getOrNull() ?: return@addListener
            provider = p
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(view.surfaceProvider) }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
            val decoder = QrDecoder()
            analysis.setAnalyzer(executor) { img ->
                val text = img.use { decoder.decode(it) }
                if (text != null && delivered.compareAndSet(false, true)) ContextCompat.getMainExecutor(ctx).execute { latest(text) }
            }
            runCatching {
                p.unbindAll()
                p.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            }.recoverCatching {
                // Devices with only a front/external camera.
                p.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis)
            }
        }, ContextCompat.getMainExecutor(ctx))
        onDispose {
            provider?.unbindAll()
            executor.shutdown()
        }
    }
    AndroidView({ view }, modifier)
}

/** ZXing QR decoding of the luminance (Y) plane; tries the inverted image too (light-on-dark desktop codes). */
internal class QrDecoder {
    private val reader = MultiFormatReader().apply {
        setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true))
    }

    fun decode(img: ImageProxy): String? {
        val plane = img.planes.firstOrNull() ?: return null
        val w = img.width; val h = img.height
        val buf = plane.buffer.duplicate().apply { rewind() }
        val row = plane.rowStride
        val y = ByteArray(w * h)
        if (row == w) buf.get(y, 0, minOf(y.size, buf.remaining()))
        else for (r in 0 until h) { buf.position(r * row); buf.get(y, r * w, minOf(w, buf.remaining())) }
        return decode(y, w, h)
    }

    fun decode(y: ByteArray, w: Int, h: Int): String? {
        val src = PlanarYUVLuminanceSource(y, w, h, 0, 0, w, h, false)
        for (s in listOf(src, src.invert())) {
            try { return reader.decodeWithState(BinaryBitmap(HybridBinarizer(s))).text } catch (_: ReaderException) { } finally { reader.reset() }
        }
        return null
    }
}
