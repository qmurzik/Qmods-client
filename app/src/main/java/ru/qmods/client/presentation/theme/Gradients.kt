package ru.qmods.client.presentation.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

object QModsGradients {
    val primaryBrand = Brush.linearGradient(listOf(AccentVioletStart, AccentCyan))
    val primaryButton = Brush.linearGradient(listOf(AccentVioletStart, AccentVioletEnd))
    val premiumGold = Brush.linearGradient(listOf(AccentGold, Color(0xFFFF7A59)))
    val cardSheen = Brush.linearGradient(listOf(SurfaceCardAlt, SurfaceCard))
    val backgroundGlow = Brush.radialGradient(
        listOf(AccentVioletStart.copy(alpha = 0.22f), BackgroundDeep)
    )
    val successSoft = Brush.linearGradient(listOf(SuccessGreen, Color(0xFF10B981)))
    val errorSoft = Brush.linearGradient(listOf(ErrorRed, Color(0xFFE11D48)))
}
