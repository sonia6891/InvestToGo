import SwiftUI

extension Color {
    /// A colour from 0xRRGGBB, as the skins store them.
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// The chosen skin and the sound setting, kept on the device.
@MainActor final class SkinStore: ObservableObject {
    /// One store for the whole app, so a skin chosen anywhere restyles the tab bar and every screen at once.
    static let shared = SkinStore()
    static let skinKey = "pocket.skin", soundKey = "pocket.sound"
    @Published var skin: Skin { didSet { UserDefaults.standard.set(skin.id, forKey: Self.skinKey); Self.current = skin } }
    /// The skin the ordinary screens' Palette reads; set before any screen draws.
    nonisolated(unsafe) static var current: Skin = Skins.named(UserDefaults.standard.string(forKey: skinKey) ?? "")
    @Published var soundOn: Bool { didSet { UserDefaults.standard.set(soundOn, forKey: Self.soundKey) } }
    /// The skin being tried on while a carousel card is held. Only the root's full-screen preview reads it; the app's
    /// own skin never changes.
    @Published var tryOn: String?

    init() {
        // UI tests start from the default look, whatever an earlier test chose.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reset") { UserDefaults.standard.removeObject(forKey: Self.skinKey) }
        var id = UserDefaults.standard.string(forKey: Self.skinKey) ?? ""
        // UI tests pick a skin with `--skin <id>` (only honoured with `--ui-testing`), after any reset.
        if args.contains("--ui-testing"), let i = args.firstIndex(of: "--skin"), args.indices.contains(i + 1) { id = args[i + 1] }
        skin = Skins.named(id)
        soundOn = (UserDefaults.standard.object(forKey: Self.soundKey) as? Bool) ?? true
        Self.current = skin
    }
    /// Switches to the skin with this id; unknown ids fall back to black-gold.
    func select(_ id: String) { skin = Skins.named(id) }
    /// Text on the skin is light (dark skins) or dark (light skins).
    var colorScheme: ColorScheme { skin.lightText ? .dark : .light }
}

extension Skin {
    var lightText: Bool { contrastRatio(colors.ink, 0x000000) > contrastRatio(colors.ink, 0xFFFFFF) }
    /// The hero panel's body colours: a dark panel on every skin, so light hero text keeps its contrast.
    var matte: UInt32 { lightText ? colors.card : colors.ink }
    var matte2: UInt32 { lightText ? colors.line : colors.ink }
    /// The 3D metal, or a plain matte stand-in for the paper and sketch skins that have none.
    var metalOrDefault: Skin.Metal { metal ?? Skin.Metal(color: colors.card, metalness: 0, roughness: 0.6) }
}
