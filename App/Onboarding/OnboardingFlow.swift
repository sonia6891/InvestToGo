import SwiftUI

/// Where a launch starts the first-launch flow (spec 5.1, 5.2), or nil for the lobby.
enum OnboardingStart: Equatable { case splash, page(Int) }

enum Onboarding {
    /// Set once the first-launch flow has been finished.
    static let doneKey = "onboarded"
    static func start(_ arguments: [String], onboarded: Bool) -> OnboardingStart? {
        nil // RED: not implemented yet
    }
}
