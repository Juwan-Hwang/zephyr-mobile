package com.zephyr.design.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.invalidateDraw
import kotlinx.coroutines.launch

/**
 * Platform-neutral press feedback: a soft highlight wash (prototype `--hl`) instead of Material ripples,
 * so Android and iOS feel the same. Fades in over 60 ms, out over 200 ms.
 */
object ZIndication : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = Node(interactionSource)
    override fun hashCode(): Int = -1
    override fun equals(other: Any?) = other === this

    private class Node(private val source: InteractionSource) : Modifier.Node(), DrawModifierNode {
        private val alpha = Animatable(0f)

        override fun onAttach() {
            coroutineScope.launch {
                source.interactions.collect { i ->
                    when (i) {
                        is PressInteraction.Press -> launch { alpha.animateTo(1f, tween(60)); invalidateDraw() }
                        is PressInteraction.Release, is PressInteraction.Cancel ->
                            launch { alpha.animateTo(0f, tween(200, easing = ZAnim.EaseOut)); invalidateDraw() }
                    }
                }
            }
        }

        override fun ContentDrawScope.draw() {
            drawContent()
            val a = alpha.value
            if (a > 0f) drawRect(Color.White.copy(alpha = 0.075f * a))
            invalidateIfAnimating()
        }

        private fun invalidateIfAnimating() { if (alpha.isRunning) invalidateDraw() }
    }
}
