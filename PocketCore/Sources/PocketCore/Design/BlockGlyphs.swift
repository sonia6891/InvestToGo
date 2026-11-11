import Foundation

/// One solid piece of a 3D numeral: a rounded box (a seven-segment stroke or the decimal point), a ring (the circles
/// of "%") or the slash of "%". Coordinates are in scene units with the whole string centred on x = 0, y = 0.
struct GlyphBlock: Equatable {
    enum Shape: Equatable { case box, ring, slash }
    var shape: Shape
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var depth: Double
    /// Rotation about the viewing axis, in radians.
    var rotation: Double = 0
    /// Polished metal when true, matte when false: the alternating blocks give the numerals their two-material look.
    var gold: Bool
}

/// Lays out a numeral string as blocks, the same geometry as the 3D concept page: digits are seven-segment strokes,
/// alternately gold on segments a/c/g and b/d/f per digit; "." "%" and "−"/"-" have their own shapes. Other characters
/// (letters, spaces, thousands separators) are skipped.
enum BlockGlyphs {
    // Thick sculpted strokes, but with open counters: the holes in 0, 6, 8, 9 must stay visible or the digits blur.
    static let width = 1.5, height = 2.3, stroke = 0.46, depth = 0.8, radius = 0.09, gap = 0.28
    static let ringRadius = 0.34

    private static let segments: [Character: (x: Double, y: Double, horizontal: Bool)] = [
        "a": (0, height / 2 - stroke / 2, true), "b": (width / 2 - stroke / 2, height / 4, false), "c": (width / 2 - stroke / 2, -height / 4, false),
        "d": (0, -height / 2 + stroke / 2, true), "e": (-(width / 2 - stroke / 2), -height / 4, false), "f": (-(width / 2 - stroke / 2), height / 4, false),
        "g": (0, 0, true)
    ]
    private static let digits: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"]
    private static let goldSets = ["acg", "bdf"]

    static func layout(_ text: String) -> (blocks: [GlyphBlock], width: Double) {
        let glyphs = text.filter { digits[$0] != nil || ".%−-".contains($0) }
        let widths = glyphs.map { $0 == "." ? stroke : ($0 == "%" ? width * 1.05 : width) }
        let total = widths.reduce(0, +) + Double(max(glyphs.count - 1, 0)) * gap
        var blocks: [GlyphBlock] = []
        var x = -total / 2, digitIndex = 0
        for (glyph, w) in zip(glyphs, widths) {
            let cx = x + w / 2
            switch glyph {
            case ".":
                blocks.append(GlyphBlock(shape: .box, x: cx, y: -height / 2 + stroke / 2, width: stroke, height: stroke, depth: depth, gold: true))
            case "%":
                let offset = w / 2 - ringRadius
                blocks.append(GlyphBlock(shape: .ring, x: cx - offset, y: 0.6, width: ringRadius * 2, height: ringRadius * 2, depth: depth * 0.5, gold: true))
                blocks.append(GlyphBlock(shape: .ring, x: cx + offset, y: -0.6, width: ringRadius * 2, height: ringRadius * 2, depth: depth * 0.5, gold: true))
                blocks.append(GlyphBlock(shape: .slash, x: cx, y: 0, width: stroke * 0.75, height: height * 1.05, depth: depth * 0.9, rotation: -0.42, gold: false))
            case "−", "-":
                blocks.append(GlyphBlock(shape: .box, x: cx, y: 0, width: width, height: stroke, depth: depth, gold: false))
            default:
                let gold = goldSets[digitIndex % 2]
                for key in digits[glyph] ?? "" {
                    let s = segments[key]!
                    let isGold = gold.contains(key)
                    blocks.append(GlyphBlock(shape: .box, x: cx + s.x, y: s.y, width: s.horizontal ? width : stroke,
                                             height: s.horizontal ? stroke : height / 2, depth: depth, gold: isGold))
                }
                digitIndex += 1
            }
            x += w + gap
        }
        // Centre on the blocks themselves, not the character cells: a seven-segment "1" uses only its right strokes.
        guard let minX = blocks.map({ $0.x - $0.width / 2 }).min(), let maxX = blocks.map({ $0.x + $0.width / 2 }).max() else { return ([], 0) }
        let shift = (minX + maxX) / 2
        return (blocks.map { var b = $0; b.x -= shift; return b }, maxX - minX)
    }
}
