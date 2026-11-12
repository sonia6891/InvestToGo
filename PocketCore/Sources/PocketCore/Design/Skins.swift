import Foundation

/// A 0xRRGGBB colour written in skins.json as "#RRGGBB".
private func hexColor(_ text: String, _ key: CodingKey, _ decoder: Decoder) throws -> UInt32 {
    var digits = text
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath + [key], debugDescription: "Not a #RRGGBB colour: \(text)"))
    }
    return value
}

/// The named colours of one skin. Screens ask for colours by name, never by code.
struct SkinColors: Equatable, Decodable {
    var page, ink, sub, dim, card, line, accent, up, down: UInt32
    /// Flat-shard and paper accents (e.g. stitch navy, mustard, cream); may be empty.
    var extra: [UInt32]
    private enum Keys: String, CodingKey { case page, ink, sub, dim, card, line, accent, up, down, extra }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func color(_ key: Keys) throws -> UInt32 { try hexColor(try c.decode(String.self, forKey: key), key, decoder) }
        page = try color(.page); ink = try color(.ink); sub = try color(.sub); dim = try color(.dim); card = try color(.card)
        line = try color(.line); accent = try color(.accent); up = try color(.up); down = try color(.down)
        extra = try c.decode([String].self, forKey: .extra).map { try hexColor($0, Keys.extra, decoder) }
    }
}

/// PostScript font names.
struct SkinFonts: Equatable, Decodable { var big, title, body, mono: String }

struct SkinStyle: Equatable, Decodable {
    enum TagKind: String, Decodable { case hexOutline, pixelBlock, paperStrip, highlighter }
    enum ButtonKind: String, Decodable { case hex, pixelBlock, paperStitch, sketchBox }
    enum StageKind: String, Decodable { case discRing, pixelFrame, paperDisc, none }
    enum CheckKind: String, Decodable { case disc, square, stitchDisc, sketchCircle }
    enum QuickKind: String, Decodable { case goldHex, pinkBlock, stitchDisc, sketchDot }
    enum ChartKind: String, Decodable { case smooth, stepped, plain, pencil }
    enum DecorKind: String, Decodable { case rays, pixelStars, seams, doodles }
    var tag: TagKind
    var button: ButtonKind
    var stage: StageKind
    var check: CheckKind
    var quick: QuickKind
    var chart: ChartKind
    var decor: DecorKind
}

struct SkinArt: Equatable, Decodable {
    enum ArtKind: String, Decodable { case render3D, voxel3D, vector }
    var kind: ArtKind
    /// Asset Catalog folder, e.g. "Skins/stitch".
    var folder: String
}

struct SkinFeedback: Equatable, Decodable {
    enum HapticKind: String, Decodable { case heavy, triple, tap, faint }
    var sound: String
    var haptic: HapticKind
}

enum SkinUnlock: Equatable, Decodable {
    case free, level(Int), member
    private enum Keys: String, CodingKey { case kind, level }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "free": self = .free
        case "member": self = .member
        case "level": self = .level(try c.decode(Int.self, forKey: .level))
        case let other: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown unlock \(other)")
        }
    }
}

/// A complete look: colours, fonts, shape kinds, art, feedback and how it unlocks. The 3D skins also carry a metal
/// material and burst colours.
struct Skin: Identifiable, Equatable, Decodable {
    struct Metal: Equatable, Decodable {
        var color: UInt32; var metalness: Double; var roughness: Double
        private enum Keys: String, CodingKey { case color, metalness, roughness }
        init(color: UInt32, metalness: Double, roughness: Double) { self.color = color; self.metalness = metalness; self.roughness = roughness }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            color = try hexColor(try c.decode(String.self, forKey: .color), Keys.color, decoder)
            metalness = try c.decode(Double.self, forKey: .metalness); roughness = try c.decode(Double.self, forKey: .roughness)
        }
    }
    var id: String
    var name: String
    /// "SKN 001"
    var code: String
    var colors: SkinColors
    var fonts: SkinFonts
    var style: SkinStyle
    var art: SkinArt
    var feedback: SkinFeedback
    var unlock: SkinUnlock
    var metal: Metal?
    var burst: [UInt32]

    private enum Keys: String, CodingKey { case id, name, code, colors, fonts, style, art, feedback, unlock, metal, burst }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); code = try c.decode(String.self, forKey: .code)
        colors = try c.decode(SkinColors.self, forKey: .colors); fonts = try c.decode(SkinFonts.self, forKey: .fonts)
        style = try c.decode(SkinStyle.self, forKey: .style); art = try c.decode(SkinArt.self, forKey: .art)
        feedback = try c.decode(SkinFeedback.self, forKey: .feedback); unlock = try c.decode(SkinUnlock.self, forKey: .unlock)
        metal = try c.decodeIfPresent(Metal.self, forKey: .metal)
        burst = try c.decode([String].self, forKey: .burst).map { try hexColor($0, Keys.burst, decoder) }
    }
}

/// The four skins, loaded once from the shared skins.json.
enum Skins {
    static let all: [Skin] = {
        guard let url = CoreBundle.bundle.url(forResource: "skins", withExtension: "json") else { fatalError("skins.json is missing from the bundle") }
        do { return try JSONDecoder().decode([Skin].self, from: try Data(contentsOf: url)) }
        catch { fatalError("skins.json could not be read: \(error)") }
    }()
    /// The free skin, black-gold.
    static var `default`: Skin { named("blackgold") }
    /// Unknown or retired ids fall back to black-gold.
    static func named(_ id: String) -> Skin { all.first { $0.id == id } ?? all.first { $0.id == "blackgold" } ?? all[0] }
    static let carouselOrder = ["voxel", "blackgold", "stitch", "sketch"]
}

/// WCAG contrast ratio of two 0xRRGGBB colours (1…21).
func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
    func luminance(_ c: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double { let s = Double(v) / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel((c >> 16) & 0xFF) + 0.7152 * channel((c >> 8) & 0xFF) + 0.0722 * channel(c & 0xFF)
    }
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}
