import Foundation

/// The network behind `OfficialHistoryClient`; tests inject a fake.
protocol HistoryFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct PublicHistoryFetcher: HistoryFetching {
    func get(_ url: URL) async throws -> Data { try await PublicHTTP.get(url) }
}

/// Price history for 回測 (spec 4, 5.6). With a 富果 key saved it is 富果's adjusted closes; without one, or when 富果
/// does not answer (a key that stopped working, a 429, a plan without history), the exchanges' own monthly closes,
/// cash dividends and ETF splits, cached on the phone and paced at one request every 2 s.
/// Requests carry only the ETF code and dates.
actor OfficialHistoryClient {
    static let shared = OfficialHistoryClient()

    private struct CachedBars: Codable { var fetched: Date; var bars: [DailyBar] }
    private struct CachedDividends: Codable { var fetched: Date; var events: [DividendEvent] }
    private struct CachedSplits: Codable { var fetched: Date; var fromYear: Int; var events: [SplitEvent] }

    private static let day: TimeInterval = 86_400
    /// Thrown when neither exchange has a single bar for the code.
    static let notFound = "找不到這檔的歷史資料"

    private let fetcher: HistoryFetching
    private let root: URL
    private let minInterval: TimeInterval
    private let clock: @Sendable () -> Date
    private let fugleKeySaved: @Sendable () -> Bool
    private let fugleBars: @Sendable (String, Int) async throws -> [DailyBar]
    /// When the next official request may start; one limiter for every endpoint.
    private var nextSlot = Date.distantPast

    init(fetcher: HistoryFetching = PublicHistoryFetcher(), root: URL? = nil, minInterval: TimeInterval = 2,
         clock: @escaping @Sendable () -> Date = { Date() },
         fugleKeySaved: @escaping @Sendable () -> Bool = { !((try? SecureKey.read()) ?? "").isEmpty },
         fugleBars: @escaping @Sendable (String, Int) async throws -> [DailyBar] = { symbol, years in
             try await Fugle.history(symbol: symbol, years: years).points.map { DailyBar(date: $0.date, close: $0.close) }
         }) {
        self.fetcher = fetcher
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history", isDirectory: true)
        self.minInterval = minInterval
        self.clock = clock
        self.fugleKeySaved = fugleKeySaved
        self.fugleBars = fugleBars
    }

    /// Whether `history` asks 富果 first (a key is saved). What a result really came from is its `fromFugle`.
    nonisolated var usesFugle: Bool { fugleKeySaved() }

    /// The months to read: `from` (or the listing month, when later) to `to`, capped at the current Taipei month.
    private func plan(from: YearMonth, to: YearMonth, listed: YearMonth?) -> [YearMonth] {
        let last = min(to, YearMonth(clock()))
        var cursor = max(from, listed ?? from)
        var months: [YearMonth] = []
        while cursor <= last { months.append(cursor); cursor = cursor.next() }
        return months
    }

    /// Bars from `from` to `to` (capped at the current Taipei month) with the dividends and splits that go with them.
    /// `market` is "TWSE" or "TPEx"; nil tries 上市 first, then 上櫃 when a month comes back empty. `listed` is the
    /// listing month from the catalogue: earlier months are not asked for. Without it months are read newest first
    /// and reading stops at three empty months in a row behind the bars (the fund was not listed yet).
    /// `progress` gets 0…1. Thrown results are never cached; a failed refresh falls back to the copy on disk.
    /// 富果 is asked only with a key saved and `fugle` true. When it fails for any reason but a cancellation,
    /// `fellBack` is called and the exchanges are read instead: a key is never a prerequisite. The result's
    /// `fromFugle` says which of the two it is.
    func history(symbol: String, market: String?, listed: YearMonth? = nil, from: YearMonth, to: YearMonth,
                 fugle: Bool = true, fellBack: @Sendable () -> Void = {},
                 progress: @Sendable (Double) -> Void) async throws -> SymbolHistory {
        guard DataChecks.code(symbol) else { throw AppDataError("ETF 代號格式不符。") }
        let months = plan(from: from, to: to, listed: listed)
        guard let firstMonth = months.first, let last = months.last else {
            return SymbolHistory(bars: [], dividends: [], splits: [], suspect: false)
        }

        if fugle, fugleKeySaved() {
            let span = (last.year - from.year) * 12 + last.month - from.month + 1
            let years = [1, 3, 5, 10, 16].first { $0 * 12 >= span - 1 } ?? 16
            do {
                let bars = try await fugleBars(symbol, years)
                    .filter { $0.date >= from.key + "-01" && $0.date <= last.key + "-31" }
                progress(1)
                return SymbolHistory(bars: bars, dividends: [], splits: [], suspect: false, fromFugle: true)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                // An invalid key, a 429, a plan without history: the exchanges have the data all the same.
                fellBack()
            }
        }

        let total = Double(months.count + (last.year - firstMonth.year + 1) + 1)
        var done = 0.0
        var saved = savedMarket(symbol)
        var resolved = market ?? saved
        var misses = 0
        var emptyRun = 0
        var bars: [DailyBar] = []
        // Newest first: a month the fund trades in settles an unknown market soonest, and the months before the
        // listing come last, where the stop rule ends them.
        for month in months.reversed() {
            try Task.checkCancellation()
            let found = try await monthBars(symbol: symbol, month: month, market: resolved)
            if resolved == nil {
                if let known = found.market {
                    resolved = known
                } else {
                    // Three months with nothing on either exchange: not a code they know. Nothing was cached for it.
                    misses += 1
                    if misses >= 3 { throw AppDataError(Self.notFound) }
                }
            }
            if let known = resolved, saved != known { saveMarket(known, symbol: symbol); saved = known }
            bars.append(contentsOf: found.bars)
            done += 1; progress(done / total)
            if found.bars.isEmpty {
                emptyRun += 1
                // Behind the bars: before the listing. With no bars at all: six empty months is enough to give up.
                if emptyRun >= (bars.isEmpty ? 6 : 3) { break }
            } else {
                emptyRun = 0
            }
        }
        guard let exchange = resolved else { throw AppDataError(Self.notFound) }
        bars.sort { $0.date < $1.date }
        guard let first = bars.first, let firstYear = Int(first.date.prefix(4)) else {
            progress(1)
            return SymbolHistory(bars: bars, dividends: [], splits: [], suspect: false)
        }

        // Dividends and splits only matter from the first bar on.
        var dividends: [DividendEvent] = []
        for year in firstYear...max(firstYear, last.year) {
            try Task.checkCancellation()
            dividends += try await yearDividends(market: exchange, year: year).filter { $0.symbol == symbol }
            done += 1; progress(min(1, done / total))
        }
        // 櫃買中心 has no split list; an unexplained jump there only marks the series as suspect.
        var splits: [SplitEvent] = []
        if exchange != "TPEx" { splits = try await splitEvents(fromYear: firstYear).filter { $0.symbol == symbol } }
        let suspect = !OfficialHistory.suspectedSplits(bars, dividends: dividends, known: splits).isEmpty
        progress(1)
        return SymbolHistory(bars: bars, dividends: dividends, splits: splits, suspect: suspect)
    }

    /// Roughly how long `history` will spend downloading what is not on the phone yet, in seconds: 2 s for each
    /// request, 8 s for each of 證交所's half-year dividend tables (they are slow to answer). 0 with a 富果 key.
    /// Only reads the cache. Without a listing month it counts every month, so it can run high.
    func estimatedSeconds(symbol: String, market: String?, listed: YearMonth? = nil, from: YearMonth, to: YearMonth) -> Int {
        guard DataChecks.code(symbol), !fugleKeySaved() else { return 0 }
        let months = plan(from: from, to: to, listed: listed)
        guard let firstMonth = months.first, let last = months.last else { return 0 }
        let now = clock()
        let known = market ?? savedMarket(symbol)
        var seconds = 0
        for month in months {
            let cached: CachedBars? = read(monthFile(symbol, month))
            if let cached, isFresh(cached.fetched, completeAt: Self.start(of: month.next()), now: now) { continue }
            seconds += 2
        }
        for year in firstMonth.year...last.year {
            let cached: CachedDividends? = read(dividendsFile(known ?? "TWSE", year))
            if let cached, isFresh(cached.fetched, completeAt: Self.start(of: YearMonth(year: year + 1, month: 1)), now: now) { continue }
            if known == "TPEx" { seconds += 2 } else { seconds += Self.date(year, 7, 1) <= now ? 16 : 8 }
        }
        if known != "TPEx" {
            let cached: CachedSplits? = read(splitsFile)
            var fresh = false
            if let cached, cached.fromYear <= firstMonth.year { fresh = isFresh(cached.fetched, completeAt: .distantFuture, now: now) }
            if !fresh { seconds += 2 }
        }
        return seconds
    }

    private func monthFile(_ symbol: String, _ month: YearMonth) -> URL {
        root.appendingPathComponent(symbol, isDirectory: true).appendingPathComponent("\(month.key).json")
    }

    private func dividendsFile(_ market: String, _ year: Int) -> URL {
        root.appendingPathComponent("dividends", isDirectory: true).appendingPathComponent("\(market)-\(year).json")
    }

    private var splitsFile: URL { root.appendingPathComponent("splits.json") }

    // MARK: Months

    /// One month of closes. A cached month is kept for good once it was fetched after the month ended; before that
    /// (the current month) it is refetched when older than a day.
    private func monthBars(symbol: String, month: YearMonth, market: String?) async throws -> (bars: [DailyBar], market: String?) {
        let file = monthFile(symbol, month)
        let old: CachedBars? = read(file)
        let now = clock()
        if let old, isFresh(old.fetched, completeAt: Self.start(of: month.next()), now: now) { return (old.bars, market) }
        do {
            var found = market
            var bars: [DailyBar] = []
            if market != "TPEx" {
                bars = try OfficialHistory.twseMonth(try await request(OfficialHistory.twseMonthURL(symbol: symbol, month: month)))
                if !bars.isEmpty { found = "TWSE" }
            }
            if market == "TPEx" || (market == nil && bars.isEmpty) {
                bars = try OfficialHistory.tpexMonth(try await request(OfficialHistory.tpexMonthURL(symbol: symbol, month: month)))
                if !bars.isEmpty { found = "TPEx" }
            }
            let prefix = month.key + "-"
            bars = bars.filter { $0.date.hasPrefix(prefix) }
            // Empty on both exchanges with the market unknown: maybe not a real code, so no folder is made for it.
            if found != nil { write(CachedBars(fetched: now, bars: bars), to: file) }
            return (bars, found)
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if let old { return (old.bars, market) }
            throw error
        }
    }

    private func savedMarket(_ symbol: String) -> String? {
        let file = root.appendingPathComponent(symbol, isDirectory: true).appendingPathComponent("market.txt")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return ["TWSE", "TPEx"].contains(text) ? text : nil
    }

    private func saveMarket(_ market: String, symbol: String) {
        let file = root.appendingPathComponent(symbol, isDirectory: true).appendingPathComponent("market.txt")
        makeDirectory(file.deletingLastPathComponent())
        try? Data(market.utf8).write(to: file, options: .atomic)
    }

    // MARK: Dividends and splits

    /// Every cash dividend on one market in one calendar year (the endpoints are market-wide), cached per year.
    private func yearDividends(market: String, year: Int) async throws -> [DividendEvent] {
        let file = dividendsFile(market, year)
        let old: CachedDividends? = read(file)
        let now = clock()
        if let old, isFresh(old.fetched, completeAt: Self.start(of: YearMonth(year: year + 1, month: 1)), now: now) { return old.events }
        do {
            var events: [DividendEvent] = []
            // 證交所's table takes 15 s or more for a whole year, so it is asked for in halves.
            let halves = market == "TPEx" ? [(1, 1, 12, 31)] : [(1, 1, 6, 30), (7, 1, 12, 31)]
            for (m0, d0, m1, d1) in halves {
                let start = Self.date(year, m0, d0)
                guard start <= now else { continue }
                let end = min(Self.date(year, m1, d1), now)
                if market == "TPEx" {
                    events += try OfficialHistory.tpexDividends(try await request(OfficialHistory.tpexDividendsURL(from: start, to: end)))
                } else {
                    events += try OfficialHistory.twseDividends(try await request(OfficialHistory.twseDividendsURL(from: start, to: end)))
                }
            }
            write(CachedDividends(fetched: now, events: events), to: file)
            return events
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if let old { return old.events }
            throw error
        }
    }

    /// 證交所's ETF splits from `fromYear` to today in one request, refetched when older than a day.
    private func splitEvents(fromYear: Int) async throws -> [SplitEvent] {
        let file = splitsFile
        let cached: CachedSplits? = read(file)
        let old = cached.flatMap { $0.fromYear <= fromYear ? $0 : nil }
        let now = clock()
        if let old, isFresh(old.fetched, completeAt: .distantFuture, now: now) { return old.events }
        do {
            let year = min(fromYear, cached?.fromYear ?? fromYear)
            let events = try OfficialHistory.splits(try await request(OfficialHistory.splitsURL(from: Self.date(year, 1, 1), to: now)))
            write(CachedSplits(fetched: now, fromYear: year, events: events), to: file)
            return events
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if let old { return old.events }
            throw error
        }
    }

    // MARK: Pacing, dates and files

    /// At least `minInterval` between the starts of two official requests, whoever asks.
    private func request(_ url: URL) async throws -> Data {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(minInterval)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        return try await fetcher.get(url)
    }

    /// Fetched after the period ended (nothing more will come), or less than a day ago.
    private func isFresh(_ fetched: Date, completeAt: Date, now: Date) -> Bool {
        fetched >= completeAt || now.timeIntervalSince(fetched) < Self.day
    }

    /// Midnight in Taipei on the first day of the month.
    private static func start(of month: YearMonth) -> Date {
        GameRules.taipei.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .distantFuture
    }

    /// Noon in Taipei on that day.
    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private func read<T: Decodable>(_ file: URL) -> T? {
        guard let bytes = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(T.self, from: bytes)
    }

    /// The cache is best effort: a failed write only means the next run downloads again.
    private func write<T: Encodable>(_ value: T, to file: URL) {
        guard let bytes = try? JSONEncoder().encode(value) else { return }
        makeDirectory(file.deletingLastPathComponent())
        try? bytes.write(to: file, options: .atomic)
    }

    private func makeDirectory(_ directory: URL) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else { return }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Everything here can be downloaded again, so it stays out of iCloud and device backups.
        var top = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? top.setResourceValues(values)
    }
}
