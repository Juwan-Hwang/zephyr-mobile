package com.zephyr.design.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.zephyr.design.theme.ZTheme

/** Search field (prototype `.fs`): 48dp rounded, magnifier, clear button when non-empty. */
@Composable
fun ZSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    focusRequester: FocusRequester? = null,
    onSubmit: (() -> Unit)? = null,
    /** Styles the text without a mirror layer, so IME composition and scrolling stay native. */
    visualTransformation: androidx.compose.ui.text.input.VisualTransformation = androidx.compose.ui.text.input.VisualTransformation.None,
    /**
     * Called with true while an IME (e.g. pinyin) is composing and false once the text is committed, so callers can
     * skip querying on half-typed Latin letters (review L-P2-5 / H-P2-12). [onValueChange] still gets every edit.
     */
    onComposingChange: ((Boolean) -> Unit)? = null,
) {
    val c = ZTheme.colors
    // Hold the full TextFieldValue so the composition range survives; adopt external text changes (clear, chip tap).
    var field by remember { mutableStateOf(TextFieldValue(value, TextRange(value.length))) }
    val shown = if (field.text == value) field else TextFieldValue(value, TextRange(value.length))
    var composing by remember { mutableStateOf(false) }
    Row(
        modifier
            .fillMaxWidth()
            .height(48.dp)
            .clip(ZTheme.shapes.surface)
            .background(c.surface3)
            .padding(start = 14.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ZIcon(ZIcons.Search, tint = c.text2, size = 20.dp)
        Spacer(Modifier.width(10.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty()) ZText(placeholder, style = ZTheme.type.body, color = c.text3, maxLines = 1)
            BasicTextField(
                value = shown,
                onValueChange = { v ->
                    field = v
                    val now = v.composition != null
                    if (now != composing) { composing = now; onComposingChange?.invoke(now) }
                    if (v.text != value) onValueChange(v.text)
                },
                singleLine = true,
                textStyle = ZTheme.type.body.copy(color = c.text1),
                cursorBrush = SolidColor(c.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit?.invoke() }),
                visualTransformation = visualTransformation,
                modifier = Modifier.fillMaxWidth().then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier),
            )
        }
        if (value.isNotEmpty()) {
            ZIconButton(ZIcons.Close, "清除", { onValueChange("") }, tint = c.text2, iconSize = 16.dp, size = 40.dp)
        }
    }
}
