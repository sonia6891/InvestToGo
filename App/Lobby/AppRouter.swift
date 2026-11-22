import Foundation

/// Where the app was asked to go from outside it. A tapped debit-day reminder asks for 記一筆; the lobby opens the
/// sheet once it is in front and the records can be read, then clears the request.
@MainActor final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var quickDCARequested = false
}
