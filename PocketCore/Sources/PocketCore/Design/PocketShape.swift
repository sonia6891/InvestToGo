import Foundation

/// The pocket's outlines in scene units, taken from the 3D concept page: a front panel with a dipped lip and a rounded
/// bottom, a taller back panel the coin drops behind the lip into, and gold stitching just inside the front edge.
enum PocketShape {
    private typealias P = SIMD2<Double>

    private static func quad(_ a: P, _ c: P, _ b: P, steps: Int) -> [P] {
        (1...steps).map { i in let t = Double(i) / Double(steps); return (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b }
    }
    private static func line(_ a: P, _ b: P, steps: Int) -> [P] { (1...steps).map { a + (b - a) * (Double($0) / Double(steps)) } }

    /// Closed outline, counter-clockwise from the top-left corner (the first point is not repeated at the end).
    static func front() -> [SIMD2<Double>] {
        let start = P(-1.25, 0.55)
        var points = [start]
        points += line(start, P(-1.25, -0.2), steps: 6)
        points += quad(P(-1.25, -0.2), P(-1.25, -1.0), P(0, -1.05), steps: 14)
        points += quad(P(0, -1.05), P(1.25, -1.0), P(1.25, -0.2), steps: 14)
        points += line(P(1.25, -0.2), P(1.25, 0.55), steps: 6)
        points += quad(P(1.25, 0.55), P(0, 0.22), start, steps: 16).dropLast()
        return points
    }

    static func back() -> [SIMD2<Double>] {
        let start = P(-1.25, 1.1)
        var points = [start]
        points += line(start, P(-1.25, -0.2), steps: 8)
        points += quad(P(-1.25, -0.2), P(-1.25, -1.0), P(0, -1.05), steps: 14)
        points += quad(P(0, -1.05), P(1.25, -1.0), P(1.25, -0.2), steps: 14)
        points += line(P(1.25, -0.2), P(1.25, 1.1), steps: 8)
        points += quad(P(1.25, 1.1), P(1.25, 1.28), P(1.07, 1.28), steps: 4)
        points += line(P(1.07, 1.28), P(-1.07, 1.28), steps: 8)
        points += quad(P(-1.07, 1.28), P(-1.25, 1.28), start, steps: 4).dropLast()
        return points
    }

    /// Dashes along the front edge, scaled 85% towards (0, −0.25): every other one of 72 equal arc-length steps.
    static func stitches() -> [(center: SIMD2<Double>, angle: Double, length: Double)] {
        let outline = front() + [front()[0]]
        var cumulative = [0.0]
        for i in 1..<outline.count { cumulative.append(cumulative[i - 1] + distance(outline[i - 1], outline[i])) }
        let total = cumulative.last!, count = 72
        func point(at s: Double) -> P {
            let i = max(1, cumulative.firstIndex { $0 >= s } ?? cumulative.count - 1)
            let t = (s - cumulative[i - 1]) / max(cumulative[i] - cumulative[i - 1], 1e-12)
            let p = outline[i - 1] + (outline[i] - outline[i - 1]) * t
            return P(p.x * 0.85, (p.y + 0.25) * 0.85 - 0.25)
        }
        return stride(from: 0, to: count, by: 2).map { k in
            let a = point(at: total * Double(k) / Double(count)), b = point(at: total * Double(k + 1) / Double(count))
            return ((a + b) / 2, atan2(b.y - a.y, b.x - a.x), distance(a, b))
        }
    }
    private static func distance(_ a: P, _ b: P) -> Double { ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() }
}
