package com.sonia.etftogo.core.design

import com.sonia.etftogo.core.support.swiftRounded
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BlockGlyphsTests {
    private val w = BlockGlyphs.width
    private val gap = BlockGlyphs.gap

    @Test fun twoDigitsUseSevenSegmentBlocks() {
        val result = BlockGlyphs.layout("12")
        assertEquals(2 + 5, result.blocks.size, "1 = bc, 2 = abged")
        assertEquals(2 * w + gap - (w - BlockGlyphs.stroke), result.width, 1e-9, "Measured on the blocks: the 1 has no left strokes")
        assertTrue(result.blocks.all { it.shape == GlyphBlock.Shape.BOX })
    }

    @Test fun percentDotAndMinus() {
        val pct = BlockGlyphs.layout("0.42%").blocks
        assertEquals(2, pct.count { it.shape == GlyphBlock.Shape.RING })
        assertEquals(1, pct.count { it.shape == GlyphBlock.Shape.SLASH })
        val minus = BlockGlyphs.layout("−0.02%")
        assertEquals(GlyphBlock.Shape.BOX, minus.blocks.first().shape)
        assertEquals(BlockGlyphs.stroke, minus.blocks.first().height, 1e-9, "The minus is one horizontal bar")
    }

    @Test fun goldAlternatesPerDigit() {
        assertEquals(6, BlockGlyphs.layout("88").blocks.count { it.gold }, "acg on the first digit, bdf on the second")
    }

    @Test fun glyphLayoutWidthsAndCentering() {
        for (text in listOf("12", "0.42%", "−0.02%", "1240")) {
            val r = BlockGlyphs.layout(text)
            val left = r.blocks.minOf { it.x - it.width / 2 }
            val right = r.blocks.maxOf { it.x + it.width / 2 }
            assertEquals(-right, left, 1e-9, text)
            assertTrue(right - left <= r.width + 1e-9, text)
        }
    }

    @Test fun digitsStayInsideTheirCellAndKeepOpenCounters() {
        val blocks = BlockGlyphs.layout("8").blocks
        val top = blocks.maxOf { it.y + it.height / 2 }
        val bottom = blocks.minOf { it.y - it.height / 2 }
        assertEquals(BlockGlyphs.height, top - bottom, 1e-9, "Vertical strokes must not stick out past the top and bottom bars")
        assertTrue(w - 2 * BlockGlyphs.stroke >= 0.35 * w, "The hole inside 0/8 must stay readable")
        assertTrue((BlockGlyphs.height - 3 * BlockGlyphs.stroke) / 2 >= 0.4, "Upper and lower holes of 8 must stay open")
    }

    @Test fun voxelizeKeepsBoundsOnGrid() {
        val cell = 0.25
        val source = BlockGlyphs.layout("12").blocks
        val voxels = BlockGlyphs.voxelize(source, cell)
        assertFalse(voxels.isEmpty())
        for (v in voxels) {
            assertEquals(cell, v.width, 1e-9)
            assertEquals(cell, v.height, 1e-9)
            assertEquals(swiftRounded(v.x / cell), v.x / cell, 1e-9, "x on the grid")
            assertEquals(swiftRounded(v.y / cell), v.y / cell, 1e-9, "y on the grid")
        }
        assertEquals(voxels.size, voxels.map { "${swiftRounded(it.x / cell).toInt()},${swiftRounded(it.y / cell).toInt()}" }.toSet().size, "No two cubes share a cell")
        fun bounds(b: List<GlyphBlock>) = listOf(b.minOf { it.x - it.width / 2 }, b.maxOf { it.x + it.width / 2 }, b.minOf { it.y - it.height / 2 }, b.maxOf { it.y + it.height / 2 })
        for ((a, b) in bounds(source).zip(bounds(voxels))) assertTrue(abs(a - b) < cell)
    }

    @Test fun unknownCharactersAreSkipped() {
        assertEquals(BlockGlyphs.layout("12").blocks, BlockGlyphs.layout("A1 2").blocks)
        assertTrue(BlockGlyphs.layout("").blocks.isEmpty())
    }
}
