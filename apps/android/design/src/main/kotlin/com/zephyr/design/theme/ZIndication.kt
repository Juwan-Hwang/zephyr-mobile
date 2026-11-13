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
 * Review D-P2-2: the wash is tokens `screen.pressed` (dark 3% white / light 3% black) so it shows in light mode too.
 */
class ZIndication(private val wash: Color) : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = Node(interactionSource, wash)
    override fun hashCode(): Int = wash.hashCode()
    override fun equals(other: Any?) = other is ZIndication && other.wash == wash

    private class Node(private val source: InteractionSource, private val wash: Color) : Modifier.Node(), DrawModifierNode {
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
            if (a > 0f) drawRect(wash.copy(alpha = wash.alpha * a))
            invalidateIfAnimating()
        }

        private fun invalidateIfAnimating() { if (alpha.isRunning) invalidateDraw() }
    }
}
