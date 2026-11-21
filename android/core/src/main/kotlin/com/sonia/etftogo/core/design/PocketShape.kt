package com.sonia.etftogo.core.design

import kotlin.math.atan2
import kotlin.math.sqrt

// Port of PocketCore Design/PocketShape.swift.

/** A point in scene units, Swift's SIMD2<Double>. */
data class Vec2(val x: Double, val y: Double) {
    operator fun plus(o: Vec2) = Vec2(x + o.x, y + o.y)
    operator fun minus(o: Vec2) = Vec2(x - o.x, y - o.y)
    operator fun times(s: Double) = Vec2(x * s, y * s)
    operator fun div(s: Double) = Vec2(x / s, y / s)
}

operator fun Double.times(v: Vec2) = Vec2(this * v.x, this * v.y)

/** One dash of the gold stitching: its middle, its direction in radians and its length. */
data class Stitch(val center: Vec2, val angle: Double, val length: Double)

/**
 * The pocket's outlines in scene units, taken from the 3D concept page: a front panel with a dipped lip and a rounded
 * bottom, a taller back panel the coin drops behind the lip into, and gold stitching just inside the front edge.
 */
object PocketShape {
    private fun quad(a: Vec2, c: Vec2, b: Vec2, steps: Int): List<Vec2> = (1..steps).map { i ->
        val t = i.toDouble() / steps
        (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b
    }

    private fun line(a: Vec2, b: Vec2, steps: Int): List<Vec2> = (1..steps).map { a + (b - a) * (it.toDouble() / steps) }

    /** Closed outline, counter-clockwise from the top-left corner (the first point is not repeated at the end). */
    fun front(): List<Vec2> {
        val start = Vec2(-1.25, 0.55)
        return listOf(start) +
            line(start, Vec2(-1.25, -0.2), 6) +
            quad(Vec2(-1.25, -0.2), Vec2(-1.25, -1.0), Vec2(0.0, -1.05), 14) +
            quad(Vec2(0.0, -1.05), Vec2(1.25, -1.0), Vec2(1.25, -0.2), 14) +
            line(Vec2(1.25, -0.2), Vec2(1.25, 0.55), 6) +
            quad(Vec2(1.25, 0.55), Vec2(0.0, 0.22), start, 16).dropLast(1)
    }

    fun back(): List<Vec2> {
        val start = Vec2(-1.25, 1.1)
        return listOf(start) +
            line(start, Vec2(-1.25, -0.2), 8) +
            quad(Vec2(-1.25, -0.2), Vec2(-1.25, -1.0), Vec2(0.0, -1.05), 14) +
            quad(Vec2(0.0, -1.05), Vec2(1.25, -1.0), Vec2(1.25, -0.2), 14) +
            line(Vec2(1.25, -0.2), Vec2(1.25, 1.1), 8) +
            quad(Vec2(1.25, 1.1), Vec2(1.25, 1.28), Vec2(1.07, 1.28), 4) +
            line(Vec2(1.07, 1.28), Vec2(-1.07, 1.28), 8) +
            quad(Vec2(-1.07, 1.28), Vec2(-1.25, 1.28), start, 4).dropLast(1)
    }

    /** Dashes along the front edge, scaled 85% towards (0, −0.25): every other one of 72 equal arc-length steps. */
    fun stitches(): List<Stitch> {
        val outline = front() + front()[0]
        val cumulative = mutableListOf(0.0)
        for (i in 1 until outline.size) cumulative.add(cumulative[i - 1] + distance(outline[i - 1], outline[i]))
        val total = cumulative.last()
        val count = 72
        fun point(s: Double): Vec2 {
            val found = cumulative.indexOfFirst { it >= s }
            val i = maxOf(1, if (found >= 0) found else cumulative.size - 1)
            val t = (s - cumulative[i - 1]) / maxOf(cumulative[i] - cumulative[i - 1], 1e-12)
            val p = outline[i - 1] + (outline[i] - outline[i - 1]) * t
            return Vec2(p.x * 0.85, (p.y + 0.25) * 0.85 - 0.25)
        }
        return (0 until count step 2).map { k ->
            val a = point(total * k / count)
            val b = point(total * (k + 1) / count)
            Stitch((a + b) / 2.0, atan2(b.y - a.y, b.x - a.x), distance(a, b))
        }
    }

    private fun distance(a: Vec2, b: Vec2): Double = sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
}
