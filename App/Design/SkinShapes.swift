import SwiftUI

// The outlines the skin components are drawn with (spec 3.3, 7.1): black-gold's hexagon, pixel's stepped frame,
// and the sketch skin's wobbly box and circle. Stitch uses rounded rectangles with a dashed seam.

/// A deterministic random sequence (SplitMix64), so a hand-drawn outline is the same on every draw.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// A value in -1…1.
    mutating func signed() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) * 2 - 1 }
}

/// The elongated hexagon: flat top and bottom, pointed ends. Each end is cut in by `cut` × the height
/// (0.28 for buttons, chips and fields).
struct HexagonShape: InsettableShape {
    var cut: CGFloat = 0.28
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        let c = min(r.height * cut, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> HexagonShape { var s = self; s.insetAmount += amount; return s }
}

/// The regular hexagon of black-gold's quick-pick button (pointy left and right).
struct RegularHexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let q = rect.width * 0.25
        p.move(to: CGPoint(x: rect.minX + q, y: rect.minY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.maxX - q, y: rect.minY + rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - q, y: rect.maxY - rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX + q, y: rect.maxY - rect.height * 0.02))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// A square with stair-stepped corners, the pixel skin's stage frame.
struct SteppedFrameShape: Shape {
    var step: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        let s = min(step, rect.width / 3, rect.height / 3)
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        var p = Path()
        p.move(to: CGPoint(x: x0 + s, y: y0))
        p.addLine(to: CGPoint(x: x1 - s, y: y0)); p.addLine(to: CGPoint(x: x1 - s, y: y0 + s))
        p.addLine(to: CGPoint(x: x1, y: y0 + s)); p.addLine(to: CGPoint(x: x1, y: y1 - s))
        p.addLine(to: CGPoint(x: x1 - s, y: y1 - s)); p.addLine(to: CGPoint(x: x1 - s, y: y1))
        p.addLine(to: CGPoint(x: x0 + s, y: y1)); p.addLine(to: CGPoint(x: x0 + s, y: y1 - s))
        p.addLine(to: CGPoint(x: x0, y: y1 - s)); p.addLine(to: CGPoint(x: x0, y: y0 + s))
        p.addLine(to: CGPoint(x: x0 + s, y: y0 + s))
        p.closeSubpath()
        return p
    }
}

/// A hand-drawn box: jittered corners, slightly bowed sides and a small overshoot where the pen closes. The jitter
/// comes from a fixed seed, so the same component is drawn the same way every time.
struct SketchBoxShape: InsettableShape {
    var seed: UInt64 = 1
    /// How far (pt) corners and side midpoints may wander.
    var wobble: CGFloat = 2.2
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount + wobble / 2, dy: insetAmount + wobble / 2)
        guard r.width > 0, r.height > 0 else { return Path() }
        var rng = SeededRandom(seed: seed)
        let w = min(wobble, r.height / 6)
        func jitter(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + rng.signed() * w, y: p.y + rng.signed() * w) }
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)].map(jitter)
        var p = Path()
        p.move(to: corners[0])
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            p.addQuadCurve(to: b, control: jitter(mid))
        }
        // The pen runs a little past where it started.
        let start = corners[0], next = corners[1]
        let length = max(1, hypot(next.x - start.x, next.y - start.y))
        let run = min(10, length * 0.12)
        p.addLine(to: CGPoint(x: start.x + (next.x - start.x) / length * run, y: start.y + (next.y - start.y) / length * run + rng.signed() * w))
        return p
    }
    func inset(by amount: CGFloat) -> SketchBoxShape { var s = self; s.insetAmount += amount; return s }
}

/// A hand-drawn circle: a slightly uneven loop that overshoots its start, from a fixed seed.
struct SketchCircleShape: InsettableShape {
    var seed: UInt64 = 1
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        var rng = SeededRandom(seed: seed)
        let start = rng.signed() * .pi, phase1 = rng.signed() * .pi, phase2 = rng.signed() * .pi
        let sweep = 2 * CGFloat.pi + 0.45
        let steps = 56
        var p = Path()
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let t = start + sweep * f
            // Uneven radius, and a slight spiral so the overshoot does not retrace the start.
            let k = 1 + 0.035 * sin(2 * t + phase1) + 0.02 * sin(3 * t + phase2) - 0.06 * f
            let point = CGPoint(x: r.midX + cos(t) * r.width / 2 * k, y: r.midY + sin(t) * r.height / 2 * k)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
    func inset(by amount: CGFloat) -> SketchCircleShape { var s = self; s.insetAmount += amount; return s }
}

/// The check mark of the solid check circles, in a 24×24 design box scaled to the rect.
struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x / 24 * rect.width, y: rect.minY + y / 24 * rect.height) }
        var p = Path()
        p.move(to: pt(5, 12.5)); p.addLine(to: pt(10, 17)); p.addLine(to: pt(19, 7))
        return p
    }
}

/// The sketch skin's one-stroke tick.
struct SketchTickShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x / 24 * rect.width, y: rect.minY + y / 24 * rect.height) }
        var p = Path()
        p.move(to: pt(4, 13))
        p.addCurve(to: pt(10, 19), control1: pt(7, 15), control2: pt(8, 17))
        p.addCurve(to: pt(21, 4), control1: pt(13, 13), control2: pt(16, 9))
        return p
    }
}

/// The dashed seam sewn into the stitch skin's paper pieces: `[6, 5]` dashes, 6pt in from the edge.
struct StitchSeam: View {
    var color: Color
    var cornerRadius: CGFloat
    var inset: CGFloat = 6
    var lineWidth: CGFloat = 1.5
    var circle = false
    var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [6, 5])
        if circle {
            Circle().inset(by: inset).stroke(color, style: style)
        } else {
            RoundedRectangle(cornerRadius: max(0, cornerRadius - inset)).stroke(color, style: style).padding(inset)
        }
    }
}

extension View {
    /// The stitch skin's paper shadow: rgba(80,52,24,.22), offset (2,3), no blur.
    func paperShadow(opacity: Double = 0.22, x: CGFloat = 2, y: CGFloat = 3) -> some View {
        shadow(color: Color(red: 80 / 255, green: 52 / 255, blue: 24 / 255).opacity(opacity), radius: 0, x: x, y: y)
    }
    /// The pixel skin's hard block shadow, 4pt down and right, no blur.
    func hardShadow(_ color: Color, offset: CGFloat = 4) -> some View {
        shadow(color: color, radius: 0, x: offset, y: offset)
    }
}
