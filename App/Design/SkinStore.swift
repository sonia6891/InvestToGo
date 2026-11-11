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
    nonisolated(unsafe) static var current: Skin = Skins.named(UserDefaults.standard.string(forKey: skinKey) ?? "") ?? Skins.default
    @Published var soundOn: Bool { didSet { UserDefaults.standard.set(soundOn, forKey: Self.soundKey) } }
    /// The 3D showcase is presented from the app root, outside the screens that redraw on a skin change, so trying
    /// skins does not close it.
    @Published var showcaseOpen = false

    init() {
        // UI tests start from the default look, whatever an earlier test chose.
        if ProcessInfo.processInfo.arguments.contains("--reset") { UserDefaults.standard.removeObject(forKey: Self.skinKey) }
        skin = Skins.named(UserDefaults.standard.string(forKey: Self.skinKey) ?? "") ?? Skins.default
        soundOn = (UserDefaults.standard.object(forKey: Self.soundKey) as? Bool) ?? true
        Self.current = skin
    }
    /// Text on the skin is light (dark skins) or dark (light skins).
    var colorScheme: ColorScheme { skin.lightText ? .dark : .light }
    func next() {
        let all = Skins.all
        skin = all[((all.firstIndex(of: skin) ?? 0) + 1) % all.count]
    }
}

extension Skin {
    var lightText: Bool { contrastRatio(foreground, 0x000000) > contrastRatio(foreground, 0xFFFFFF) }
}
