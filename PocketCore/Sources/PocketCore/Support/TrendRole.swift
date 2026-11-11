import Foundation

/// Which way a change went, and the colour Taiwanese investors read it in: gains red, losses green (spec D4).
enum TrendRole: Equatable {
    case up, down, flat
    init(_ value: Double) { self = value > 0 ? .up : (value < 0 ? .down : .flat) }
    var colorName: String {
        switch self { case .up: return "red"; case .down: return "green"; case .flat: return "muted" }
    }
}
