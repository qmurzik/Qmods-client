package ru.qmods.client.presentation.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import ru.qmods.client.presentation.theme.SurfaceCard
import ru.qmods.client.presentation.theme.SurfaceCardAlt

/** A single shimmering placeholder block, used to build skeleton loading states. */
@Composable
fun SkeletonBlock(
    modifier: Modifier = Modifier,
    height: Dp = 16.dp,
    cornerRadius: Dp = 8.dp,
    widthFraction: Float = 1f
) {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val translate by transition.animateFloat(
        initialValue = -400f,
        targetValue = 400f,
        animationSpec = infiniteRepeatable(
            animation = tween(1100, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "skeletonShimmer"
    )

    val brush = Brush.linearGradient(
        colors = listOf(SurfaceCard, SurfaceCardAlt, SurfaceCard),
        start = Offset(translate - 200f, 0f),
        end = Offset(translate + 200f, 0f)
    )

    androidx.compose.foundation.layout.Box(
        modifier = modifier
            .fillMaxWidth(widthFraction)
            .height(height)
            .clip(RoundedCornerShape(cornerRadius))
            .background(brush)
    )
}

@Composable
fun SkeletonCard(modifier: Modifier = Modifier, lines: Int = 3) {
    GradientCard(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SkeletonBlock(height = 20.dp, cornerRadius = 6.dp, widthFraction = 0.5f)
            repeat(lines) {
                SkeletonBlock(height = 14.dp)
            }
        }
    }
}

@Composable
fun SkeletonList(modifier: Modifier = Modifier, itemCount: Int = 4) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        repeat(itemCount) {
            SkeletonCard(lines = 2)
        }
    }
}
