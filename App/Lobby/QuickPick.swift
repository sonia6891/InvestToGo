import SwiftUI

/// The quick pick (spec 4.3): the screen dims and five discs pop out along an arc above the bar's quick button.
/// Tapping a disc switches straight to that feature; tapping the dimmed screen folds it away. With Reduce Motion
/// the discs fade in where they stand.
struct QuickPick: View {
    @Binding var open: Bool
    var pick: (Feature) -> Void
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @State private var shown = false

    /// Disc diameter.
    private let disc: CGFloat = 66

    var body: some View {
        ZStack {
            Color.black.opacity(skin.lightText ? 0.6 : 0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { open = false }
                .accessibilityLabel("收起快選")
                .accessibilityAddTraits(.isButton)
            GeometryReader { geo in
                let features = Feature.allCases
                ForEach(Array(features.enumerated()), id: \.element) { index, feature in
                    let target = Self.position(index, of: features.count, in: geo.size)
                    let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height - GameBottomBar.height / 2)
                    let moving = !reduceMotion && !shown
                    button(feature)
                        .position(moving ? origin : target)
                        .scaleEffect(moving ? 0.3 : 1)
                        .opacity(shown ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.68).delay(Double(index) * 0.03), value: shown)
                }
            }
        }
        .onAppear { shown = true }
    }

    private func button(_ feature: Feature) -> some View {
        Button { pick(feature) } label: {
            VStack(spacing: 6) {
                discView(feature)
                SkinTag(feature.title)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feature.title)
        .accessibilityIdentifier("quick-\(feature.rawValue)")
    }

    /// The skin's stage as the disc; a skin without a stage (sketch) gets a hand-drawn paper disc, so the object
    /// never floats over the dimmed page.
    @ViewBuilder private func discView(_ feature: Feature) -> some View {
        let art = SkinImage(feature.art).frame(width: disc * 0.72, height: disc * 0.72)
        if skin.style.stage == .none {
            art.frame(width: disc, height: disc)
                .background(SketchCircleShape(seed: 7).fill(skin.color(\.card)))
                .overlay(SketchCircleShape(seed: 7).stroke(skin.color(\.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round)))
        } else {
            SkinStage(size: disc) { art }
        }
    }

    /// Discs sit on an arc centred on the quick button, from lower left (160°) over the top to lower right (20°),
    /// clear of the bar's labels.
    static func position(_ index: Int, of count: Int, in size: CGSize) -> CGPoint {
        let centre = CGPoint(x: size.width / 2, y: size.height - GameBottomBar.height / 2)
        let fraction = count > 1 ? Double(index) / Double(count - 1) : 0.5
        let angle = (160 - 140 * fraction) * .pi / 180
        let rx = min(140, size.width / 2 - 52), ry: CGFloat = 170
        return CGPoint(x: centre.x + rx * CGFloat(cos(angle)), y: centre.y - 34 - ry * CGFloat(sin(angle)))
    }
}
