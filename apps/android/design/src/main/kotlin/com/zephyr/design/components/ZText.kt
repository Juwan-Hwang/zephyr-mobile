package com.zephyr.design.components

import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import com.zephyr.design.theme.ZTheme

/** Text primitive. Colour defaults to text1; never use Material Text in pages. */
@Composable
fun ZText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = ZTheme.type.body,
    color: Color = ZTheme.colors.text1,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Ellipsis,
    softWrap: Boolean = true,
) {
    BasicText(text, modifier, style.copy(color = color), maxLines = maxLines, overflow = overflow, softWrap = softWrap)
}

@Composable
fun ZText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    style: TextStyle = ZTheme.type.body,
    color: Color = ZTheme.colors.text1,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Ellipsis,
) {
    BasicText(text, modifier, style.copy(color = color), maxLines = maxLines, overflow = overflow)
}
