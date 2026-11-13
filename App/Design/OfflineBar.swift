import Network
import SwiftUI

/// Whether the phone can reach the network. UI tests force it off with `--offline` (only with `--ui-testing`).
@MainActor final class Connectivity: ObservableObject {
    static let shared = Connectivity()
    @Published private(set) var offline: Bool
    static let forcedOffline: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--offline")
    }()
    private let monitor = NWPathMonitor()

    private init() {
        offline = Self.forcedOffline
        guard !Self.forcedOffline else { return }
        monitor.pathUpdateHandler = { path in
            let unreachable = path.status != .satisfied
            Task { @MainActor in Connectivity.shared.offline = unreachable }
        }
        monitor.start(queue: DispatchQueue(label: "ETFToGo.connectivity"))
    }
}

/// The thin strip at the very top while offline (spec 9 離線): 「離線中 · 顯示 11/12 09:00 的資料」.
struct OfflineBar: View {
    @EnvironmentObject var store: PortfolioStore
    @Environment(\.skin) private var skin

    /// The bar's words for the time of the data on screen; nil when that time is unknown.
    nonisolated static func text(_ date: Date?) -> String {
        guard let date else { return "離線中 · 顯示上次的資料" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.dateFormat = "MM/dd HH:mm"
        return "離線中 · 顯示 \(format.string(from: date)) 的資料"
    }

    var body: some View {
        Text(Self.text(store.lastDataDate))
            .skinFont(.mono(11))
            .foregroundStyle(skin.color(\.sub))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.vertical, 5)
            .background(skin.color(\.card))
            .overlay(alignment: .bottom) { Rectangle().fill(skin.color(\.line)).frame(height: 1) }
            .accessibilityIdentifier("offline-bar")
    }
}

/// A read that failed (spec 9 讀取失敗): what happened in plain words and 「再試一次」. The screen keeps showing the
/// last good data underneath; `lastUpdated` says when that data is from.
struct LoadFailed: View {
    var message: String
    var retry: () -> Void
    var lastUpdated: String?

    init(message: String, retry: @escaping () -> Void, lastUpdated: String?) {
        self.message = message; self.retry = retry; self.lastUpdated = lastUpdated
    }

    var body: some View {
        SkinCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(message).skinFont(.body(14)).skinForeground(\.ink).fixedSize(horizontal: false, vertical: true)
                if let lastUpdated {
                    Text("下方是 \(lastUpdated) 的資料").skinFont(.mono(11)).skinForeground(\.sub)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("load-failed-last")
                }
                SkinButton("再試一次", action: retry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("load-failed")
    }
}

extension PortfolioStore {
    /// When the newest data on screen was fetched: the latest saved or exchange quote, else the ETF list's day.
    var lastDataDate: Date? {
        let fetched = data.quotes.values.map(\.fetchedAt) + [daily?.fetchedAt].compactMap { $0 }
        if let newest = fetched.max() { return newest }
        return catalog.flatMap { DataChecks.date($0.fetchedDay) }
    }
}

/// "2026/10/15" from "2026-10-15".
func slashDay(_ day: String) -> String { day.replacingOccurrences(of: "-", with: "/") }
