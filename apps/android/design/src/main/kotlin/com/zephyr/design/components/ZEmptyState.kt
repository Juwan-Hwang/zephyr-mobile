package com.zephyr.design.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

@Composable
fun ZEmptyState(title: String, modifier: Modifier = Modifier, message: String? = null, action: String? = null, onAction: (() -> Unit)? = null) {
    Column(
        modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ZText(title, style = ZTheme.type.headline, color = ZTheme.colors.text2)
        if (message != null) ZText(message, style = ZTheme.type.footnote.copy(textAlign = TextAlign.Center), color = ZTheme.colors.text3)
        if (action != null && onAction != null) ZButton(action, onAction, Modifier.padding(top = 12.dp), kind = ZButtonKind.Secondary)
    }
}
