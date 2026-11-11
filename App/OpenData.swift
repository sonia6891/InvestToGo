import Foundation

extension OpenData {
    static func fetch() async throws -> Day {
        async let listed = load(twseQuotes, decodeTWSE)
        async let otc = load(tpexQuotes, decodeTPEx)
        async let taiex = load(twseIndices, decodeTAIEX)
        async let tpexValue = load(tpexIndex, decodeTPExIndex)
        var quotes = await listed ?? [:]
        quotes.merge(await otc ?? [:]) { first, _ in first }
        let indices: [String: Quote] = ["taiex": (await taiex).flatMap { $0 }, "tpex": (await tpexValue).flatMap { $0 }].compactMapValues { $0 }
        guard !quotes.isEmpty || !indices.isEmpty else { throw AppDataError("暫時取不到收盤資料，保留上次報價。") }
        return Day(quotes: quotes, indices: indices, fetchedAt: Date())
    }

    /// Nil when the request or the decoding fails.
    private static func load<T>(_ url: URL, _ decode: (Data) throws -> T) async -> T? {
        guard let bytes = try? await PublicHTTP.get(url) else { return nil }
        return try? decode(bytes)
    }
}
extension PortfolioStore {
    var hasFugleKey: Bool { !((try? SecureKey.read()) ?? "").isEmpty }
    /// The latest trading day's prices from the open data, fetched only while either exchange is behind the day that
    /// should be out: on its own at most every 20 minutes (the exchanges publish some time after the close), when the
    /// viewer asks (`manual`) at most once a minute. Returns whether data is at hand.
    @discardableResult
    func refreshDaily(manual: Bool = false) async -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return daily != nil }
        let behind = (daily?.settledDay ?? "") < OpenData.expectedDay()
        let since = dailyAttemptAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard behind, since >= (manual ? 60 : 20 * 60) else { return daily != nil }
        dailyAttemptAt = Date()
        guard let fresh = try? await OpenData.fetch() else { return daily != nil }
        // One exchange may not have published the new day yet, so each code keeps its newest close;
        // codes that stopped trading drop out after two weeks.
        var merged = daily ?? fresh
        merged.quotes.merge(fresh.quotes) { old, new in new.date >= old.date ? new : old }
        merged.indices.merge(fresh.indices) { old, new in new.date >= old.date ? new : old }
        if let latest = DataChecks.date(merged.day) {
            let cutoff = DataChecks.day(latest.addingTimeInterval(-14 * 86400))
            merged.quotes = merged.quotes.filter { $0.value.date >= cutoff }
        }
        merged.fetchedAt = fresh.fetchedAt
        daily = merged
        indices.merge(merged.indices) { old, new in new.fetchedAt > old.fetchedAt ? new : old }
        saveDaily()
        return true
    }
    /// On every return to the app: the latest closes, and with a Fugle key the indices outside the session
    /// (during it LiveFeed streams).
    func followMarket() async {
        await refreshDaily()
        if hasFugleKey && !TaiwanMarket.isOpen() { await refreshIndices() }
    }
}
