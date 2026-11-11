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
