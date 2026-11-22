package com.sonia.etftogo.core.design

import com.sonia.etftogo.core.support.swiftRounded

// Port of PocketCore Design/BlockGlyphs.swift.

/**
 * One solid piece of a 3D numeral: a rounded box (a seven-segment stroke or the decimal point), a ring (the circles of
 * "%") or the slash of "%". Coordinates are in scene units with the whole string centred on x = 0, y = 0.
 */
data class GlyphBlock(
    val shape: Shape,
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
    val depth: Double,
    /** Rotation about the viewing axis, in radians. */
    val rotation: Double = 0.0,
    /** Polished metal when true, matte when false: the alternating blocks give the numerals their two-material look. */
    val gold: Boolean,
) {
    enum class Shape { BOX, RING, SLASH }
}

/** A laid-out numeral string and its width measured on the blocks. */
data class GlyphLayout(val blocks: List<GlyphBlock>, val width: Double)

/**
 * Lays out a numeral string as blocks, the same geometry as the 3D concept page: digits are seven-segment strokes,
 * alternately gold on segments a/c/g and b/d/f per digit; "." "%" and "−"/"-" have their own shapes. Other characters
 * (letters, spaces, thousands separators) are skipped.
 */
object BlockGlyphs {
    // Thick sculpted strokes, but with open counters: the holes in 0, 6, 8, 9 must stay visible or the digits blur.
    const val width = 1.5
    const val height = 2.3
    const val stroke = 0.46
    const val depth = 0.8
    const val radius = 0.09
    const val gap = 0.28
    const val ringRadius = 0.34

    private class Segment(val x: Double, val y: Double, val horizontal: Boolean)

    private val segments: Map<Char, Segment> = mapOf(
        'a' to Segment(0.0, height / 2 - stroke / 2, true), 'b' to Segment(width / 2 - stroke / 2, height / 4, false),
        'c' to Segment(width / 2 - stroke / 2, -height / 4, false), 'd' to Segment(0.0, -height / 2 + stroke / 2, true),
        'e' to Segment(-(width / 2 - stroke / 2), -height / 4, false), 'f' to Segment(-(width / 2 - stroke / 2), height / 4, false),
        'g' to Segment(0.0, 0.0, true),
    )
    private val digits: Map<Char, String> = mapOf(
        '0' to "abcdef", '1' to "bc", '2' to "abged", '3' to "abgcd", '4' to "fgbc", '5' to "afgcd", '6' to "afgedc", '7' to "abc", '8' to "abcdefg", '9' to "abcdfg",
    )
    private val goldSets = listOf("acg", "bdf")

    fun layout(text: String): GlyphLayout {
        val glyphs = text.filter { it in digits || it in ".%−-" }
        val widths = glyphs.map { if (it == '.') stroke else if (it == '%') width * 1.05 else width }
        val total = widths.fold(0.0) { sum, w -> sum + w } + maxOf(glyphs.length - 1, 0) * gap
        val blocks = mutableListOf<GlyphBlock>()
        var x = -total / 2
        var digitIndex = 0
        for ((glyph, w) in glyphs.toList().zip(widths)) {
            val cx = x + w / 2
            when (glyph) {
                '.' -> blocks.add(GlyphBlock(GlyphBlock.Shape.BOX, cx, -height / 2 + stroke / 2, stroke, stroke, depth, gold = true))
                '%' -> {
                    val offset = w / 2 - ringRadius
                    blocks.add(GlyphBlock(GlyphBlock.Shape.RING, cx - offset, 0.6, ringRadius * 2, ringRadius * 2, depth * 0.5, gold = true))
                    blocks.add(GlyphBlock(GlyphBlock.Shape.RING, cx + offset, -0.6, ringRadius * 2, ringRadius * 2, depth * 0.5, gold = true))
                    blocks.add(GlyphBlock(GlyphBlock.Shape.SLASH, cx, 0.0, stroke * 0.75, height * 1.05, depth * 0.9, rotation = -0.42, gold = false))
                }
                '−', '-' -> blocks.add(GlyphBlock(GlyphBlock.Shape.BOX, cx, 0.0, width, stroke, depth, gold = false))
                else -> {
                    val gold = goldSets[digitIndex % 2]
                    for (key in digits[glyph] ?: "") {
                        val s = segments.getValue(key)
                        blocks.add(GlyphBlock(GlyphBlock.Shape.BOX, cx + s.x, s.y, if (s.horizontal) width else stroke,
                            if (s.horizontal) stroke else height / 2, depth, gold = key in gold))
                    }
                    digitIndex += 1
                }
            }
            x += w + gap
        }
        // Centre on the blocks themselves, not the character cells: a seven-segment "1" uses only its right strokes.
        val minX = blocks.minOfOrNull { it.x - it.width / 2 } ?: return GlyphLayout(emptyList(), 0.0)
        val maxX = blocks.maxOf { it.x + it.width / 2 }
        val shift = (minX + maxX) / 2
        return GlyphLayout(blocks.map { it.copy(x = it.x - shift) }, maxX - minX)
    }

    /**
     * Re-lays the boxes as square cells of side `cell` for the pixel skin's voxel numerals. Cell centres sit on multiples
     * of `cell`; each box keeps the cells whose centres round into it, so every edge moves by at most half a cell.
     * Overlapping strokes share a cell once (the first box's colour wins). Rings and slashes pass through unchanged.
     */
    fun voxelize(blocks: List<GlyphBlock>, cell: Double): List<GlyphBlock> {
        if (!(cell > 0)) return blocks
        fun cells(centre: Double, size: Double): IntRange {
            val low = swiftRounded((centre - size / 2) / cell + 0.5).toInt()
            val high = swiftRounded((centre + size / 2) / cell - 0.5).toInt()
            return low..maxOf(low, high)
        }
        val taken = mutableSetOf<Pair<Int, Int>>()
        val result = mutableListOf<GlyphBlock>()
        for (block in blocks) {
            if (block.shape != GlyphBlock.Shape.BOX) { result.add(block); continue }
            for (i in cells(block.x, block.width)) {
                for (j in cells(block.y, block.height)) {
                    if (taken.add(i to j)) result.add(GlyphBlock(GlyphBlock.Shape.BOX, i * cell, j * cell, cell, cell, block.depth, gold = block.gold))
                }
            }
        }
        return result
    }
}
