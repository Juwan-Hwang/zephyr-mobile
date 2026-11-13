package com.zephyr.app.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.zephyr.design.components.ZIcon
import com.zephyr.design.components.ZIcons
import com.zephyr.design.components.ZText
import com.zephyr.design.components.zPressable
import com.zephyr.design.theme.ZTheme

/** Library sub-page frame: "‹ 资料库" back link, optional trailing action, large title (prototype `.pg`). */
@Composable
fun PageScaffold(
    back: String,
    title: String,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = ZTheme.colors
    Column(Modifier.fillMaxSize().background(c.bg).statusBarsPadding()
        // Review L-P2-13: landscape cutouts take horizontal room too.
        .windowInsetsPadding(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal))) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(start = 8.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.zPressable(label = "返回$back", onClick = onBack).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                ZIcon(ZIcons.Back, tint = c.accent, size = 22.dp)
                Spacer(Modifier.width(2.dp))
                ZText(back, style = ZTheme.type.body.copy(fontSize = ZTheme.type.headline.fontSize), color = c.accent)
            }
            Spacer(Modifier.weight(1f))
            trailing?.invoke()
        }
        ZText(title, Modifier.padding(horizontal = 22.dp).semantics { heading() }, style = ZTheme.type.title)
        Spacer(Modifier.height(12.dp))
        Box(Modifier.weight(1f)) { Column(Modifier.fillMaxSize(), content = content) }
    }
}
