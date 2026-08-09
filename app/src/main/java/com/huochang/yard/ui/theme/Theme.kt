package com.huochang.yard.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/** Brand palette (mirrors the PWA CSS tokens). */
val Green = Color(0xFF34C759)
val Red = Color(0xFFFF3B30)
val Orange = Color(0xFFFF9500)
val Indigo = Color(0xFF5856D6)

fun Color.Companion.fromHex(hex: String): Color {
    val h = hex.removePrefix("#")
    return Color(
        h.substring(0, 2).toInt(16),
        h.substring(2, 4).toInt(16),
        h.substring(4, 6).toInt(16)
    )
}

private val DarkColorScheme = darkColorScheme(
    background = Color(0xFF000000),
    surface = Color(0xFF1C1C1E),
    surfaceVariant = Color(0xFF2C2C2E)
)

private val LightColorScheme = lightColorScheme(
    background = Color(0xFFF2F2F7),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFF8F8FC)
)

/**
 * App theme. The accent (primary) color is driven by the user-chosen tint,
 * matching the PWA's configurable `--blue` token.
 */
@Composable
fun YardAppTheme(
    tintHex: String,
    darkTheme: Boolean,
    content: @Composable () -> Unit
) {
    val tint = Color.fromHex(tintHex)

    val light = lightColorScheme(
        primary = tint,
        onPrimary = Color.White,
        primaryContainer = tint.copy(alpha = 0.12f),
        onPrimaryContainer = tint,
        background = LightColorScheme.background,
        surface = LightColorScheme.surface,
        surfaceVariant = LightColorScheme.surfaceVariant,
        error = Red,
        onError = Color.White
    )
    val dark = darkColorScheme(
        primary = tint,
        onPrimary = Color.White,
        primaryContainer = tint.copy(alpha = 0.2f),
        onPrimaryContainer = tint,
        background = DarkColorScheme.background,
        surface = DarkColorScheme.surface,
        surfaceVariant = DarkColorScheme.surfaceVariant,
        error = Red,
        onError = Color.White
    )

    val colorScheme = if (darkTheme) dark else light

    val view = LocalView.current
    if (!view.isInEditMode) {
        val window = (view.context as Activity).window
        WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
