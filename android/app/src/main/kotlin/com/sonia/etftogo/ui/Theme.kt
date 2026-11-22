package com.sonia.etftogo.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** 黑金, the default 外觀主題, until A2b brings the full theme system. Background is the iPhone LaunchBackground. */
object Palette {
    val background = Color(0xFF1A1A1D)
    val card = Color(0xFF26262B)
    val gold = Color(0xFFD9B45A)
    val text = Color(0xFFF2EFE6)
    val muted = Color(0xFFA8A49A)
}

@Composable
fun EtfTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Palette.gold,
            onPrimary = Palette.background,
            background = Palette.background,
            onBackground = Palette.text,
            surface = Palette.card,
            onSurface = Palette.text,
            onSurfaceVariant = Palette.muted,
        ),
        content = content,
    )
}
