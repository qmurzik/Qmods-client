package ru.qmods.client.presentation.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import ru.qmods.client.presentation.theme.CardCornerRadius
import ru.qmods.client.presentation.theme.QModsGradients
import ru.qmods.client.presentation.theme.SurfaceBorder
import ru.qmods.client.presentation.theme.SurfaceCard

/** The base premium card used throughout the app: soft border, subtle sheen, rounded corners. */
@Composable
fun GradientCard(
    modifier: Modifier = Modifier,
    backgroundBrush: Brush = QModsGradients.cardSheen,
    borderColor: androidx.compose.ui.graphics.Color = SurfaceBorder,
    contentPadding: androidx.compose.foundation.layout.PaddingValues =
        androidx.compose.foundation.layout.PaddingValues(20.dp),
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(CardCornerRadius))
            .background(backgroundBrush)
            .border(1.dp, borderColor, RoundedCornerShape(CardCornerRadius))
            .padding(contentPadding)
    ) {
        content()
    }
}

@Composable
fun SolidCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(CardCornerRadius))
            .background(SurfaceCard)
            .border(1.dp, SurfaceBorder, RoundedCornerShape(CardCornerRadius))
            .padding(20.dp)
    ) {
        content()
    }
}
