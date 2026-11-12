import SwiftUI

/// The bar under every feature screen (spec 4.3): 「‹ 大廳」 on the left, the skin's quick-pick button in the middle,
/// the page name in gold on the right. The quick button opens the quick pick over a dimmed screen and turns into ✕.
/// Put it in a full-screen overlay aligned to the bottom; screens keep `GameBottomBar.height` clear with
/// `gameBarSpace()`.
struct GameBottomBar: View {
    let title: String
    var onLobby: () -> Void
    var onPick: (Feature) -> Void
    @Environment(\.skin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    static let height: CGFloat = 76

    var body: some View {
        ZStack(alignment: .bottom) {
            if open {
                QuickPick(open: $open) { feature in
                    open = false
                    onPick(feature)
                }
                .transition(.opacity)
            }
            bar
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.18), value: open)
    }

    private var bar: some View {
        let label = skin.lightText ? skin.color(\.accent) : skin.color(\.ink)
        return HStack(spacing: 0) {
            Button(action: onLobby) {
                Text("‹ 大廳").skinFont(.mono(12)).skinForeground(\.sub)
                    .frame(minWidth: 80, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回大廳")
            .accessibilityIdentifier("bar-lobby")
            Spacer(minLength: 8)
            Button { open.toggle() } label: { QuickButton(open: open) }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "收起快選" : "快選")
                .accessibilityIdentifier("bar-quick")
            Spacer(minLength: 8)
            Text(title).skinFont(.mono(12)).foregroundStyle(label)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(minWidth: 80, alignment: .trailing)
                .allowsHitTesting(false)
                .accessibilityIdentifier("bar-title")
        }
        .padding(.horizontal, 24)
        .frame(height: Self.height)
        .background(alignment: .bottom) {
            // Content scrolls under the bar's soft top edge; the background never takes taps meant for it.
            LinearGradient(stops: [.init(color: skin.color(\.page).opacity(0), location: 0), .init(color: skin.color(\.page), location: 0.4)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

/// The quick-pick button in the skin's style (`style.quick`): a gold hexagon (black-gold), a pink block with a white
/// frame and hard shadow (pixel), a red paper disc with a seam (stitch), a hand-drawn yellow circle (sketch).
/// Shows ✕ while the quick pick is open.
struct QuickButton: View {
    let open: Bool
    @Environment(\.skin) private var skin

    var body: some View {
        ZStack {
            chrome
            if open {
                Text("✕").font(.system(size: 22, weight: .bold)).foregroundStyle(skin.onFill(skin.colors.accent))
            }
        }
        .frame(width: 66, height: 62)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var chrome: some View {
        let accent = skin.color(\.accent)
        switch skin.style.quick {
        case .goldHex:
            RegularHexagonShape().fill(accent).frame(width: 66, height: 60)
        case .pinkBlock:
            Rectangle().fill(accent).hardShadow(skin.extra(2, or: \.line), offset: 5)
                .overlay(Rectangle().strokeBorder(skin.color(\.ink), lineWidth: 3))
                .frame(width: 58, height: 58)
        case .stitchDisc:
            Circle().fill(accent).paperShadow(opacity: 0.3, x: 3, y: 4)
                .overlay(StitchSeam(color: skin.color(\.card), cornerRadius: 0, inset: 8, lineWidth: 2, circle: true))
                .frame(width: 62, height: 62)
        case .sketchDot:
            SketchCircleShape(seed: 58).fill(accent)
                .overlay(SketchCircleShape(seed: 58).stroke(skin.color(\.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)))
                .frame(width: 58, height: 58)
        }
    }
}
