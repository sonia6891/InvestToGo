package com.sonia.etftogo.core.design

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PocketShapeTests {
    private fun mirrored(points: List<Vec2>): Boolean = points.all { p -> points.any { abs(it.x + p.x) < 0.03 && abs(it.y - p.y) < 0.03 } }

    @Test fun outlinesAreSymmetricAndBackIsTaller() {
        val front = PocketShape.front()
        val back = PocketShape.back()
        assertTrue(front.size > 40)
        assertTrue(mirrored(front))
        assertTrue(mirrored(back))
        assertEquals(back.minOf { it.y }, front.minOf { it.y }, 0.01, "Same rounded bottom")
        assertTrue(back.maxOf { it.y } > front.maxOf { it.y } + 0.5, "The back panel stands above the front lip")
    }

    @Test fun stitchesAreEvenAndInsideThePocket() {
        val stitches = PocketShape.stitches()
        val front = PocketShape.front()
        assertEquals(36, stitches.size)
        val lengths = stitches.map { it.length }
        assertTrue(lengths.max() - lengths.min() < 0.02, "Evenly spaced along the edge")
        assertTrue(stitches.all { abs(it.center.x) < front.maxOf { p -> p.x } && it.center.y > front.minOf { p -> p.y } })
    }
}

class SkinsTests {
    @Test fun fourSkinsInOrder() {
        assertEquals(listOf("blackgold", "voxel", "stitch", "sketch"), Skins.all.map { it.id })
        assertEquals(listOf("黑金", "像素", "縫線", "手繪"), Skins.all.map { it.name })
        assertEquals("blackgold", Skins.default.id)
        assertEquals(listOf("voxel", "blackgold", "stitch", "sketch"), Skins.carouselOrder)
    }

    @Test fun colorsMatchSpec() {
        val gold = Skins.named("blackgold").colors
        assertEquals(0x1A1A1Du, gold.page); assertEquals(0xF4F1E8u, gold.ink); assertEquals(0xF2B632u, gold.accent)
        assertEquals(0xF25C54u, gold.up); assertEquals(0x3BB273u, gold.down)
        assertEquals(0x1B1F4Bu, Skins.named("voxel").colors.page); assertEquals(0xFF3D8Bu, Skins.named("voxel").colors.accent)
        val stitch = Skins.named("stitch").colors
        assertEquals(0xE9DCC3u, stitch.page); assertEquals(0x3B2A1Au, stitch.ink); assertEquals(0xC9573Fu, stitch.accent)
        assertEquals(listOf(0x2F4A6Du, 0xE3A82Bu, 0xF7F0E1u), stitch.extra)
        val sketch = Skins.named("sketch").colors
        assertEquals(0xFAF8F3u, sketch.page); assertEquals(0x1F1F1Fu, sketch.ink); assertEquals(0xF2D16Bu, sketch.accent)
    }

    @Test fun skinTextContrast() {
        for (skin in Skins.all) {
            assertTrue(contrastRatio(skin.colors.ink, skin.colors.page) >= 4.5, "${skin.id} ink")
            assertTrue(contrastRatio(skin.colors.sub, skin.colors.page) >= 4.5, "${skin.id} sub")
            assertTrue(contrastRatio(skin.colors.up, skin.colors.page) >= 3, "${skin.id} up")
            assertTrue(contrastRatio(skin.colors.down, skin.colors.page) >= 3, "${skin.id} down")
        }
        assertEquals(21.0, contrastRatio(0xFFFFFFu, 0x000000u), 0.01)
    }

    @Test fun unknownOrRetiredSkinFallsBackToBlackGold() {
        for (id in listOf("ember", "ice", "", "nope")) assertEquals("blackgold", Skins.named(id).id, id)
        assertEquals("stitch", Skins.named("stitch").id)
    }

    @Test fun unlockRules() {
        assertEquals(SkinUnlock.Free, Skins.named("blackgold").unlock)
        assertEquals(SkinUnlock.Level(5), Skins.named("sketch").unlock)
        assertEquals(SkinUnlock.Level(10), Skins.named("voxel").unlock)
        assertEquals(SkinUnlock.Member, Skins.named("stitch").unlock)
    }

    /** Black-gold is free, sketch opens at LV.5, pixel at LV.10, stitch only for members; members get all four. */
    @Test fun isUnlocked() {
        fun open(level: Int, member: Boolean) = Skins.all.filter { Skins.isUnlocked(it, level, member) }.map { it.id }
        assertEquals(listOf("blackgold"), open(1, false))
        assertEquals(listOf("blackgold"), open(4, false))
        assertEquals(listOf("blackgold", "sketch"), open(5, false))
        assertEquals(listOf("blackgold", "sketch"), open(9, false))
        assertEquals(listOf("blackgold", "voxel", "sketch"), open(10, false))
        assertEquals(listOf("blackgold", "voxel", "sketch"), open(40, false), "Stitch never opens by level")
        assertEquals(listOf("blackgold", "voxel", "stitch", "sketch"), open(1, true))
    }

    @Test fun onlyVectorSkinsHaveNoMetal() {
        for (id in listOf("stitch", "sketch")) {
            assertEquals(SkinArt.ArtKind.VECTOR, Skins.named(id).art.kind, id)
            assertNull(Skins.named(id).metal, id)
        }
        for (id in listOf("blackgold", "voxel")) assertNotNull(Skins.named(id).metal, id)
        assertEquals(SkinArt.ArtKind.RENDER_3D, Skins.named("blackgold").art.kind)
        assertEquals(SkinArt.ArtKind.VOXEL_3D, Skins.named("voxel").art.kind)
    }

    @Test fun fontsAndFeedback() {
        assertEquals(SkinFonts("Anton-Regular", "NotoSansTC-Bold", "NotoSansTC-Medium", "JetBrainsMono-Regular"), Skins.named("blackgold").fonts)
        assertEquals(SkinFonts("PressStart2P-Regular", "DotGothic16-Regular", "DotGothic16-Regular", "PressStart2P-Regular"), Skins.named("voxel").fonts)
        assertEquals(SkinFonts("BreeSerif-Regular", "NotoSerifTC-Bold", "NotoSerifTC-Medium", "BreeSerif-Regular"), Skins.named("stitch").fonts)
        assertEquals(SkinFonts("Caveat-Regular", "LXGWWenKaiTC-Medium", "LXGWWenKaiTC-Medium", "LXGWWenKaiTC-Medium", bigBold = true, bigOverhang = 0.12), Skins.named("sketch").fonts)
        // Only the sketch skin's big face is drawn bold and needs room for its overhang; the others keep the defaults.
        for (id in listOf("blackgold", "voxel", "stitch")) {
            assertFalse(Skins.named(id).fonts.bigBold, id)
            assertEquals(0.0, Skins.named(id).fonts.bigOverhang, id)
        }
        assertEquals(listOf("thud", "chip", "snip", "scribble"), Skins.all.map { it.feedback.sound })
        assertEquals(SkinFeedback.HapticKind.FAINT, Skins.named("sketch").feedback.haptic)
        assertEquals("Skins/stitch", Skins.named("stitch").art.folder)
    }

    @Test fun artNamesAndFolders() {
        assertEquals(listOf("hero_dollar", "pocket", "pocket_icon", "find", "dividends", "tools", "achievements", "crown", "calc", "fees", "reminder", "goal", "badge"),
            SkinArtName.entries.map { it.rawValue })
        assertEquals(listOf("Skins/blackgold", "Skins/voxel", "Skins/stitch", "Skins/sketch"), Skins.all.map { it.art.folder })
        assertEquals("Skins/stitch/find", Skins.named("stitch").art.image(SkinArtName.FIND))
        assertEquals("Skins/sketch/tally_5", Skins.named("sketch").art.image(named = "tally_5"))
    }
}
