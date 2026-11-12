import SwiftUI

// The skin component kit's foundation: the current skin in the environment, its fonts and its named colours.
// Screens read these and the components in SkinComponents.swift; only the components switch on `skin.style`.

private struct SkinKey: EnvironmentKey {
    /// Outside an injected tree (previews, renderers) the stored skin still applies.
    static var defaultValue: Skin { SkinStore.current }
}

extension EnvironmentValues {
    /// The skin every kit component draws with. Injected at the app root from `SkinStore.shared.skin`.
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

/// The four type roles of a skin (spec 3.2). Sizes are the design sizes; they follow Dynamic Type.
enum SkinFont {
    case big(CGFloat), title(CGFloat), body(CGFloat), mono(CGFloat)

    var size: CGFloat {
        switch self { case .big(let s), .title(let s), .body(let s), .mono(let s): return s }
    }

    func font(_ skin: Skin) -> Font {
        let name: String, style: Font.TextStyle
        switch self {
        case .big: name = skin.fonts.big; style = .largeTitle
        case .title: name = skin.fonts.title; style = .title3
        case .body: name = skin.fonts.body; style = .body
        case .mono: name = skin.fonts.mono; style = .caption
        }
        let font = Font.custom(name, size: size, relativeTo: style)
        // A variable big face registers under its Regular instance; the skin says when the canvas draws it bold.
        return isBig && skin.fonts.bigBold ? font.weight(.bold) : font
    }

    var isBig: Bool { if case .big = self { return true } else { return false } }
}

private struct SkinFontModifier: ViewModifier {
    @Environment(\.skin) private var skin
    let role: SkinFont
    @ViewBuilder func body(content: Content) -> some View {
        if role.isBig {
            // Big numerals grow at most to about 1.3× (spec 3.2); callers let them wrap or scale down past that.
            // Tracking, unlike padding, widens the text's own frame past the last glyph, so a face whose ink overhangs
            // its advance (skin.fonts.bigOverhang, in em) is not cut off where a single line is drawn to its bounds.
            content.font(role.font(skin)).tracking(skin.fonts.bigOverhang * role.size)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        } else {
            content.font(role.font(skin))
        }
    }
}

extension View {
    /// Sets the current skin's font for a type role.
    func skinFont(_ role: SkinFont) -> some View { modifier(SkinFontModifier(role: role)) }
    /// Foreground in one of the current skin's named colours, e.g. `.skinForeground(\.sub)`.
    func skinForeground(_ name: KeyPath<SkinColors, UInt32>) -> some View { modifier(SkinColorModifier(name: name, background: false)) }
    /// Background in one of the current skin's named colours.
    func skinBackground(_ name: KeyPath<SkinColors, UInt32>) -> some View { modifier(SkinColorModifier(name: name, background: true)) }
}

private struct SkinColorModifier: ViewModifier {
    @Environment(\.skin) private var skin
    let name: KeyPath<SkinColors, UInt32>
    let background: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if background { content.background(skin.color(name)) } else { content.foregroundStyle(skin.color(name)) }
    }
}

extension Skin {
    /// One of this skin's named colours: `skin.color(\.accent)`. Views get the skin from `@Environment(\.skin)`.
    func color(_ name: KeyPath<SkinColors, UInt32>) -> Color { Color(rgb: colors[keyPath: name]) }
    /// A flat-shard / paper accent from `colors.extra`, or `fallback` when the skin has fewer.
    func extra(_ index: Int, or fallback: KeyPath<SkinColors, UInt32>) -> Color {
        colors.extra.indices.contains(index) ? Color(rgb: colors.extra[index]) : color(fallback)
    }
    /// Text that reads on a fill of `fill`: whichever of the skin's page or ink colour contrasts more.
    func onFill(_ fill: UInt32) -> Color {
        Color(rgb: contrastRatio(colors.page, fill) >= contrastRatio(colors.ink, fill) ? colors.page : colors.ink)
    }
}

/// A stable seed from text (Swift's `hashValue` changes on every launch), so a hand-drawn outline around the same
/// label is drawn the same way every time.
enum SkinSeed {
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }
}
