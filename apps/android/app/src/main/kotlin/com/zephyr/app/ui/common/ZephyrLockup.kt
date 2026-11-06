package com.zephyr.app.ui.common

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zephyr.app.R
import com.zephyr.design.components.ZText
import com.zephyr.design.theme.ZTheme

/** Brand lockup: Z glyph + "Zephyr" wordmark (design/prototype/brand/app-lockup.svg). */
@Composable
fun ZephyrLockup(modifier: Modifier = Modifier) {
    Row(modifier.clearAndSetSemantics { contentDescription = "Zephyr" }, verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(R.drawable.ic_stat_zephyr), null, Modifier.size(20.dp), colorFilter = ColorFilter.tint(ZTheme.colors.text1))
        Spacer(Modifier.width(4.dp))
        ZText("Zephyr", style = ZTheme.type.headline.copy(fontWeight = FontWeight.Bold, fontSize = 19.sp, letterSpacing = (-0.2).sp))
    }
}
