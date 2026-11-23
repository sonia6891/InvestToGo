import Foundation

/// The app's own link, `etftogo://lobby`: what a tap on the 「連續定投」 widget opens. The widget extension compiles
/// this file too, so it must not use anything the extension cannot.
enum AppURL {
    static let lobby = URL(string: "etftogo://lobby")!

    /// True for the scheme `etftogo` with the host `lobby`, and nothing else.
    static func opensLobby(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "etftogo" && url.host?.lowercased() == "lobby"
    }
}
