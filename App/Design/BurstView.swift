import SwiftUI

/// Comic-style shards that fly out from a point and fade, drawn behind the 3D hero when a coin lands.
struct BurstView: View {
    /// Changing this starts a new burst.
    var trigger: Int
    var center: UnitPoint
    var colors: [Color]
    @Environment(\.motionReduced) private var reduceMotion
    @State private var start: Date?
    @State private var shards: [(angle: Double, spread: Double, inner: Double, reach: Double, color: Int)] = []

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start, !shards.isEmpty else { return }
                let p = timeline.date.timeIntervalSince(start) / 0.65
                guard p < 1 else { return }
                let eased = 1 - pow(1 - p, 3)
                context.opacity = p < 0.55 ? 1 : 1 - (p - 0.55) / 0.45
                let c = CGPoint(x: size.width * center.x, y: size.height * center.y), longest = max(size.width, size.height) * 0.8
                for s in shards {
                    let ri = s.inner + eased * 60, ro = s.inner + eased * s.reach * longest
                    var path = Path()
                    path.move(to: CGPoint(x: c.x + cos(s.angle) * ri, y: c.y + sin(s.angle) * ri))
                    path.addLine(to: CGPoint(x: c.x + cos(s.angle - s.spread) * ro, y: c.y + sin(s.angle - s.spread) * ro))
                    path.addLine(to: CGPoint(x: c.x + cos(s.angle + s.spread) * ro, y: c.y + sin(s.angle + s.spread) * ro))
                    path.closeSubpath()
                    context.fill(path, with: .color(colors.isEmpty ? .white : colors[s.color % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            // Reduce Motion: no shards at all (spec 3.5).
            guard !reduceMotion else { return }
            shards = (0..<18).map { i in (Double(i) / 18 * 2 * .pi + Double.random(in: -0.12...0.12), Double.random(in: 0.05...0.14), Double.random(in: 26...56), Double.random(in: 0.45...1), i) }
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { start = nil }
        }
    }
}

/// How a skin plays the coin drop, from its art kind and never its id (spec 7.1 投幣動畫, first version): the 3D skins
/// drop a coin with shards, the vector skins pop their picture with 「+1」. (Stitch's 「縫進口袋」 and sketch's 「正字多一筆」
/// come later.)
enum CoinDropStyle: Equatable {
    case coinAndShards, popPlusOne
    init(_ skin: Skin) { self = skin.art.kind == .vector ? .popPlusOne : .coinAndShards }
}

/// A coin falling onto a screen's hero (spec 3.5): it drops from above while turning, lands with the skin's confirm
/// sound and haptic and a burst of shards, then fades. Vector skins pop their pocket picture with 「+1」 instead. With
/// Reduce Motion it only fades in and out where it lands: no fall, no turning, no pop, no shards. Increasing `trigger`
/// plays it once; the first value plays nothing.
struct CoinDrop: View {
    var trigger: Int
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var offset: CGFloat = 0
    @State private var turn: Double = 0
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0
    @State private var bursts = 0
    /// While shards fly, an element named `burst` exists so UI tests can see them; never with VoiceOver (decoration).
    @State private var bursting = false

    var body: some View {
        let style = CoinDropStyle(skin)
        ZStack {
            if !reduceMotion && style == .coinAndShards {
                BurstView(trigger: bursts, center: .center, colors: skin.burst.map { Color(rgb: $0) })
            }
            Group {
                switch style {
                case .coinAndShards:
                    ZStack {
                        Circle().fill(skin.color(\.accent))
                        Circle().strokeBorder(skin.color(\.ink).opacity(0.35), lineWidth: 3).padding(7)
                    }
                    .frame(width: 46, height: 46)
                    .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0))
                case .popPlusOne:
                    VStack(spacing: 2) {
                        Text("+1").skinFont(.big(28)).skinForeground(\.ink)
                        SkinImage(.pocketIcon).frame(width: 64, height: 64)
                    }
                }
            }
            .scaleEffect(scale)
            .offset(y: offset)
            .opacity(opacity)
            .accessibilityHidden(true)
            if bursting && !voiceOver {
                Color.black.opacity(0.01).frame(width: 2, height: 2)
                    .accessibilityElement()
                    .accessibilityLabel("碎片")
                    .accessibilityIdentifier("burst")
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in play(style) }
    }

    private func play(_ style: CoinDropStyle) {
        var still = Transaction(); still.disablesAnimations = true
        if reduceMotion {
            withTransaction(still) { offset = 0; turn = 0; scale = 1; opacity = 0 }
            withAnimation(.easeOut(duration: 0.25)) { opacity = 1 } completion: {
                land()
                withAnimation(.easeIn(duration: 0.35).delay(0.4)) { opacity = 0 }
            }
        } else if style == .popPlusOne {
            withTransaction(still) { offset = 0; turn = 0; scale = 0.4; opacity = 1 }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) { scale = 1 } completion: {
                    withAnimation(.easeOut(duration: 0.3).delay(0.35)) { opacity = 0 }
                }
                land()
            }
        } else {
            withTransaction(still) { offset = -170; turn = 0; scale = 1; opacity = 1 }
            // The start position is set first, so the fall animates from above rather than from where the last coin was.
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.5)) { offset = 0; turn = 540 } completion: {
                    land()
                    bursts += 1
                    bursting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bursting = false }
                    withAnimation(.easeOut(duration: 0.3).delay(0.15)) { opacity = 0 }
                }
            }
        }
    }

    private func land() { ConfirmFeedback.confirm(skin) }
}
