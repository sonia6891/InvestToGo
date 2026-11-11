import SwiftUI

/// Comic-style shards that fly out from a point and fade, drawn behind the 3D hero when a coin lands.
struct BurstView: View {
    /// Changing this starts a new burst.
    var trigger: Int
    var center: UnitPoint
    var colors: [Color]
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
            shards = (0..<18).map { i in (Double(i) / 18 * 2 * .pi + Double.random(in: -0.12...0.12), Double.random(in: 0.05...0.14), Double.random(in: 26...56), Double.random(in: 0.45...1), i) }
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { start = nil }
        }
    }
}

/// The still poster behind a hero: long comic shards radiating from the hero, in the skin's colours. Drawn once from a
/// fixed seed so the composition is the same on every visit.
struct PosterShards: View {
    var center: UnitPoint
    var colors: [Color]
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func random() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
            let c = CGPoint(x: size.width * center.x, y: size.height * center.y), longest = max(size.width, size.height)
            for i in 0..<14 {
                let angle = Double(i) / 14 * 2 * .pi + (random() - 0.5) * 0.3
                let spread = 0.03 + random() * 0.07, inner = longest * (0.16 + random() * 0.08), outer = longest * (0.55 + random() * 0.4)
                var path = Path()
                path.move(to: CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: c.x + cos(angle - spread) * outer, y: c.y + sin(angle - spread) * outer))
                path.addLine(to: CGPoint(x: c.x + cos(angle + spread) * outer, y: c.y + sin(angle + spread) * outer))
                path.closeSubpath()
                context.opacity = i % 3 == 0 ? 0.95 : 0.55
                context.fill(path, with: .color(colors.isEmpty ? .white : colors[i % colors.count]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
