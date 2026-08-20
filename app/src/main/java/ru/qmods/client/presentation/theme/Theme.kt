package ru.qmods.client.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val QModsDarkColorScheme = darkColorScheme(
    primary = AccentVioletStart,
    onPrimary = TextOnAccent,
    primaryContainer = AccentVioletEnd,
    onPrimaryContainer = TextOnAccent,
    secondary = AccentCyan,
    onSecondary = BackgroundDeep,
    tertiary = AccentGold,
    onTertiary = BackgroundDeep,
    background = BackgroundDeep,
    onBackground = TextPrimary,
    surface = SurfaceCard,
    onSurface = TextPrimary,
    surfaceVariant = SurfaceCardAlt,
    onSurfaceVariant = TextSecondary,
    outline = SurfaceBorder,
    error = ErrorRed,
    onError = TextOnAccent
)

/**
 * The product is dark-only by design (premium fintech look), so [isSystemInDarkTheme] is not
 * consulted - a device set to light mode still gets the QMods dark palette.
 */
@Composable
fun QModsTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = QModsDarkColorScheme,
        typography = QModsTypography,
        shapes = QModsShapes,
        content = content
    )
}
