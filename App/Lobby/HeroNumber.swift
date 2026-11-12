import SwiftUI
import UIKit

/// The lobby's hero: the DCA streak as the skin's big numeral, with its caption below (spec 4.2, 5.3). The 3D
/// skins build it from blocks (`PocketHero`); the vector skins set their `digit_N` images side by side — stitch
/// alternates its mustard set and sews them on the cloth patch, sketch lays them on a highlighter stroke. Large
/// values shrink to fit the width; nothing is cut.
struct HeroNumber: View {
    let value: Int
    let caption: String
    /// VoiceOver label; the streak by default.
    var label: String? = nil
    /// Tapping the numeral (the lobby opens the DCA history).
    var action: (() -> Void)? = nil
    @Environment(\.skin) private var skin

    /// The numeral's zone. The lobby draws `SkinDecor` behind exactly this height, never behind the caption.
    static let numeralHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 2) {
            numeral
                .frame(height: Self.numeralHeight)
                .contentShape(Rectangle())
                // Simultaneous: the 3D numeral tilts under a drag that starts at a touch, which would swallow a tap.
                .simultaneousGesture(TapGesture().onEnded { action?() })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label ?? "連續定投 \(value) 個月")
                .accessibilityAddTraits(action == nil ? [] : .isButton)
                .accessibilityAction { action?() }
                .frame(maxWidth: .infinity)
            Text(caption).skinFont(.big(40)).skinForeground(\.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var numeral: some View {
        switch skin.art.kind {
        case .render3D, .voxel3D:
            // The 3D scene scales its blocks to 70% of its frame, so any count fits.
            PocketHero(value: "\(value)", skin: skin)
                .frame(maxWidth: .infinity)
        case .vector:
            ViewThatFits(in: .horizontal) {
                digits(height: 170)
                digits(height: 130)
                digits(height: 100)
                digits(height: 76)
                digits(height: 56)
                digits(height: 40)
            }
        }
    }

    private func digits(height: CGFloat) -> some View {
        let characters = Array(String(value))
        let alternate = Self.hasImage(skin.art.image(named: "digit_0_b"))
        return HStack(spacing: height * 0.04) {
            ForEach(characters.indices, id: \.self) { i in
                let name = "digit_\(characters[i])" + (alternate && i % 2 == 1 ? "_b" : "")
                SkinImage(named: name).frame(height: height)
            }
        }
        .padding(.horizontal, height * 0.16).padding(.vertical, height * 0.12)
        .background { backing(height: height) }
        .fixedSize()
    }

    /// What the vector digits sit on: the stitch cloth patch when the skin has one, a highlighter stroke when its
    /// tags are highlighter marks.
    @ViewBuilder private func backing(height: CGFloat) -> some View {
        let patch = skin.art.image(named: "patch")
        if Self.hasImage(patch) {
            Image(patch).resizable().paperShadow()
        } else if skin.style.tag == .highlighter {
            Rectangle().fill(skin.color(\.accent)).frame(height: height * 0.42).rotationEffect(.degrees(-2))
        }
    }

    private static func hasImage(_ name: String) -> Bool { UIImage(named: name) != nil }
}
