package com.sonia.etftogo.core.support

/** Which way a change went, and the colour Taiwanese investors read it in: gains red, losses green. */
enum class TrendRole {
    UP, DOWN, FLAT;

    val colorName: String get() = when (this) { UP -> "red"; DOWN -> "green"; FLAT -> "muted" }

    companion object {
        /** Swift `TrendRole(_:)`; NaN compares false both ways and so is flat. */
        fun of(value: Double): TrendRole = if (value > 0) UP else if (value < 0) DOWN else FLAT
    }
}
