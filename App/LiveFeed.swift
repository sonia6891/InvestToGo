import Foundation

/* ---------- live market data during trading hours ----------
   With the viewer's Fugle key: streaming (aggregates channel) for the symbols that matter most, the key sent only in
   the auth message, never in a URL; REST within the plan's rate limit for the rest and for both indices. Free plan:
   1 connection, 5 subscriptions, 60 intraday requests a minute; paid plans: whole-market snapshot every 5 seconds.
   Without a key there is no intraday feed: prices are each trading day's close from the exchanges' open data (OpenData).
   It runs only while the app is active and the Taiwan market is open, and stops when the app goes to the background. */

/// Taiwan regular session in Asia/Taipei, with a few minutes either side for the opening trial match and closing prints.
enum TaiwanMarket {
    static let zone = TimeZone(identifier: "Asia/Taipei")!
    static func isOpen(_ date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday), let hour = parts.hour, let minute = parts.minute else { return false }
        let minutes = hour * 60 + minute
        return minutes >= 8 * 60 + 55 && minutes <= 13 * 60 + 40
    }
}

/// One aggregates push: the latest trade (or trial match) and the day's figures.
struct LiveTick: Equatable {
    var symbol: String
    var price: Double
    var change: Double?
    var changePercent: Double?
    var open: Double?
    var high: Double?
    var low: Double?
    var volume: Double?
    var date: String?
    var trial: Bool
    /// During a trial match: the last real trade (closePrice).
    var lastTrade: Double? = nil
}
enum LiveEvent: Equatable {
    case authenticated
    case subscribed([String: String])
    case tick(LiveTick)
    case error(code: Int, message: String)
    case heartbeat
    case other
}
/// Message shapes of Fugle's streaming API, kept apart from the connection so they can be tested.
enum LiveProtocol {
    static let endpoint = URL(string: "wss://api.fugle.tw/marketdata/v1.0/stock/streaming")!
    static func text(_ object: [String: Any]) -> String {
        guard let bytes = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(data: bytes, encoding: .utf8) ?? "{}"
    }
    static func auth(key: String) -> String { text(["event": "auth", "data": ["apikey": key]]) }
    static func subscribe(_ symbols: [String]) -> String { text(["event": "subscribe", "data": ["channel": "aggregates", "symbols": symbols]]) }
    static func unsubscribe(_ ids: [String]) -> String { text(["event": "unsubscribe", "data": ["ids": ids]]) }
    static func ping() -> String { text(["event": "ping", "data": ["state": "etftogo"]]) }

    /// A JSON number. `is Bool` cannot tell them apart, because NSNumber 0 and 1 bridge to Bool; the CF type can.
    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }
    private static func number(_ value: Any?) -> Double? {
        guard let double = numeric(value)?.doubleValue, double.isFinite else { return nil }
        return double
    }
    private static func identifier(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        return numeric(value)?.stringValue
    }
    static func parse(_ raw: String) -> LiveEvent {
        guard let bytes = raw.data(using: .utf8), let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], let event = root["event"] as? String else { return .other }
        switch event {
        case "authenticated":
            return .authenticated
        case "heartbeat", "pong":
            return .heartbeat
        case "subscribed":
            // One symbol answers with an object, several with an array; some versions put the fields at the top level.
            let entries: [[String: Any]]
            if let list = root["data"] as? [[String: Any]] { entries = list } else if let one = root["data"] as? [String: Any] { entries = [one] } else { entries = [root] }
            var map: [String: String] = [:]
            for entry in entries {
                let channel = (entry["channel"] as? String) ?? "aggregates"
                if channel == "aggregates", let symbol = entry["symbol"] as? String, let id = identifier(entry["id"]) { map[symbol] = id }
            }
            return .subscribed(map)
        case "data":
            guard (root["channel"] as? String) == "aggregates", let data = root["data"] as? [String: Any], let tick = tick(data) else { return .other }
            return .tick(tick)
        case "error":
            let data = root["data"] as? [String: Any]
            let code = Int(number(root["code"]) ?? number(data?["code"]) ?? 0)
            let message = (data?["message"] as? String) ?? (root["message"] as? String) ?? ""
            return .error(code: code, message: message)
        default:
            return .other
        }
    }
    static func tick(_ data: [String: Any]) -> LiveTick? {
        guard let symbol = data["symbol"] as? String, DataChecks.code(symbol) else { return nil }
        let trial = (data["isTrial"] as? Bool) ?? false
        // During the trial match only lastPrice moves; closePrice is the last real trade.
        let price = trial ? number(data["lastPrice"]) : (number(data["closePrice"]) ?? number(data["lastPrice"]))
        guard let price, price > 0 else { return nil }
        let total = data["total"] as? [String: Any]
        return LiveTick(symbol: symbol, price: price, change: number(data["change"]), changePercent: number(data["changePercent"]), open: number(data["openPrice"]), high: number(data["highPrice"]), low: number(data["lowPrice"]), volume: number(total?["tradeVolume"]), date: data["date"] as? String, trial: trial, lastTrade: trial ? number(data["closePrice"]) : nil)
    }
    /// Field by field, because a push does not carry everything a REST quote does. Only the same trading day's
    /// figures carry over; the currency always does.
    static func merge(_ previous: Quote?, _ tick: LiveTick, now: Date = Date()) -> Quote {
        let sameDay = previous.map { tick.date == nil || tick.date == $0.date } ?? false
        var quote = sameDay ? previous! : Quote(symbol: tick.symbol, price: tick.price, changePercent: nil, date: tick.date ?? DataChecks.day(), fetchedAt: now, currency: previous?.currency)
        quote.symbol = tick.symbol
        quote.price = tick.price
        quote.change = tick.change ?? quote.change
        quote.changePercent = tick.changePercent ?? quote.changePercent
        quote.open = tick.open ?? quote.open
        quote.high = tick.high ?? quote.high
        quote.low = tick.low ?? quote.low
        quote.volume = tick.volume ?? quote.volume
        quote.date = tick.date ?? quote.date
        quote.fetchedAt = now
        quote.trial = tick.trial ? true : nil
        quote.source = nil
        if quote.currency == nil { quote.currency = guessCurrency(tick.symbol) }
        return quote
    }
    /// The last real trade behind a pushed quote: the quote itself, or during a trial match the day's earlier real one,
    /// else one rebuilt from the push's closePrice (the change measured from the same reference price).
    static func realTrade(_ quote: Quote, _ tick: LiveTick, known: Quote?) -> Quote? {
        guard tick.trial else { return quote }
        // The earlier one only while it is still the latest trade; the push says otherwise once the auction moved on.
        if let known, known.date == quote.date, known.trial != true, tick.lastTrade == nil || tick.lastTrade == known.price { return known }
        guard let trade = tick.lastTrade, trade > 0 else { return nil }
        var real = quote
        real.price = trade; real.trial = nil
        if let change = tick.change, tick.price - change > 0 {
            let reference = tick.price - change
            real.change = ((trade - reference) * 10000).rounded() / 10000
            real.changePercent = ((trade - reference) / reference * 10000).rounded() / 100
        } else {
            real.change = nil; real.changePercent = nil
        }
        return real.isValid ? real : nil
    }
    /// Foreign-currency share classes end in C or K; everything else on TWSE/TPEx trades in NT$.
    static func guessCurrency(_ symbol: String) -> String { symbol.hasSuffix("C") || symbol.hasSuffix("K") ? "UNKNOWN" : "TWD" }
    /// Seconds before reconnect attempt `n`: exponential up to a minute, with jitter so devices do not reconnect together.
    static func backoff(attempt: Int, random: Double = Double.random(in: 0...1)) -> TimeInterval {
        let base = min(pow(2, Double(max(attempt, 1) - 1)), 60)
        return base / 2 + base / 2 * random
    }
}

struct LiveStatus: Equatable {
    /// Market open, key present, app active.
    var running = false
    var marketOpen = false
    var connecting = false
    var reconnecting = false
    var subscribed: Set<String> = []
    var pollSeconds = 0
    var paidPlan = false
    /// A Fugle key is saved; without one there is no intraday feed, only each day's close.
    var hasKey = false
    var note = ""
    var lastUpdate: Date?
}

@MainActor final class LiveFeed {
    private unowned let store: PortfolioStore
    private var apiKey = ""
    private var active = false
    private var loop: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var generation = 0
    private var authed = false
    private var subs: [String: String] = [:]
    private var pending: [String: Date] = [:]
    private var cap = Int.max
    private var paid: Bool?
    private var retry = 0
    private var fails = 0
    /// Fugle refused the key (stream error 1000 or HTTP 401): no streaming until the key changes.
    private var keyRejected = false
    /// Streaming rests for a while after connections that never authenticated (no network, captive portal).
    private var pausedUntil = Date.distantPast
    private var note = ""
    private var busyUntil = Date.distantPast
    private var backoffUntil = Date.distantPast
    private var reconnectAt: Date?
    private var lastMessage = Date.distantPast
    private var lastPing = Date.distantPast
    private var lastLoop: Date?
    private var pollAt = Date.distantPast
    private var indicesAt = Date.distantPast
    private var pollIndex = 0
    private var pollSeconds = 0
    private var polling = false
    private var catchUp: [String] = []
    private var buffer: [String: Quote] = [:]
    private var flushQueued = false
    private var lastUpdate: Date?
    private var wasWanted = false

    private static let pausedNote = "連不上即時串流，先改為定時更新，稍後自動再試。"
    /// The last real trade of each symbol, saved instead of a trial-match price when the app leaves.
    private var lastReal: [String: Quote] = [:]

    init(store: PortfolioStore) { self.store = store }

    private var wanted: Bool {
        active && !apiKey.isEmpty && TaiwanMarket.isOpen() && !ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }
    private var limit: Int { min(cap, paid == true ? 280 : 5) }

    /// The app became active: start the loop and connect if the market is open. Coming back from a brief
    /// interruption (Control Center, a call banner) keeps the connection as it is.
    func start() {
        guard !active else { return }
        active = true
        apiKey = (try? SecureKey.read()) ?? ""
        if loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await self?.step()
                }
            }
        }
        resume()
    }
    /// The app left the foreground: close the stream, stop requests, keep the last prices of holdings and watchlist.
    func stop() {
        active = false; wasWanted = false
        loop?.cancel(); loop = nil
        closeSocket()
        keepLastPrices()
        publish()
    }
    /// A new or removed key, or a new plan: start over.
    func restart() {
        keyRejected = false; fails = 0; cap = .max; paid = nil; note = ""; busyUntil = .distantPast; backoffUntil = .distantPast
        stop(); start()
    }
    /// Which symbols matter changed (a detail page opened, holdings or watchlist edited).
    func syncSoon() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            self.sync()
        }
    }

    private func resume() {
        retry = 0; closeSocket(); reconnectAt = nil
        indicesAt = .distantPast; pollAt = .distantPast; lastLoop = Date()
        // Each return to the app tries streaming again, unless Fugle refused the key.
        fails = 0; pausedUntil = .distantPast
        if note == Self.pausedNote { note = "" }
        wasWanted = wanted
        guard wanted else { publish(); return }
        // The stream may not resend current prices, so the most important symbols are fetched once first.
        catchUp = paid == true ? [] : Array(targets().prefix(5))
        connect()
        publish()
    }
    private func step() async {
        let now = Date()
        // Measured from the end of the previous step, so a slow request is not taken for a suspended app.
        let gap = lastLoop.map { now.timeIntervalSince($0) } ?? 0
        defer { lastLoop = Date() }
        let want = wanted
        // The session just ended: save the day's last prices of holdings and watchlist.
        if wasWanted, !want { keepLastPrices() }
        wasWanted = want
        guard want else { if socket != nil { closeSocket() }; publish(); return }
        if gap > 15 { resume(); return } // the app was suspended and its timers froze
        if let socket, authed {
            if now.timeIntervalSince(lastMessage) > 35 { closeSocket(); scheduleReconnect() }
            else if now.timeIntervalSince(lastPing) > 25 { lastPing = now; send(LiveProtocol.ping(), on: socket) }
        } else if socket == nil, (reconnectAt ?? .distantPast) <= now {
            connect()
        }
        // A manual refresh draws on the same request allowance, so polling waits for it.
        guard now >= backoffUntil, !polling, !store.refreshing else { return }
        if now.timeIntervalSince(indicesAt) >= 15 { indicesAt = now; await pollIndices() }
        else if now >= pollAt { await poll() }
    }

    /* ---------- stream ---------- */
    private func connect() {
        guard socket == nil, !keyRejected, Date() >= busyUntil, Date() >= pausedUntil, wanted else { return }
        reconnectAt = nil
        generation += 1
        let current = generation
        let task = URLSession.shared.webSocketTask(with: LiveProtocol.endpoint)
        socket = task; authed = false; subs = [:]; pending = [:]; lastMessage = Date()
        task.resume()
        send(LiveProtocol.auth(key: apiKey), on: task)
        receive(task, generation: current)
        publish()
    }
    private func send(_ text: String, on task: URLSessionWebSocketTask) { task.send(.string(text)) { _ in } }
    private func receive(_ task: URLSessionWebSocketTask, generation current: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == current, self.socket === task else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let bytes): self.handle(String(data: bytes, encoding: .utf8) ?? "")
                    @unknown default: break
                    }
                    if self.socket === task { self.receive(task, generation: current) }
                case .failure:
                    self.socketEnded(task)
                }
            }
        }
    }
    private func handle(_ text: String) {
        lastMessage = Date()
        switch LiveProtocol.parse(text) {
        case .authenticated:
            authed = true; retry = 0; fails = 0; note = ""; subs = [:]; pending = [:]; lastPing = Date()
            sync()
        case .subscribed(let map):
            for (symbol, id) in map { subs[symbol] = id; pending[symbol] = nil }
            publish()
        case .tick(let tick):
            let previous = buffer[tick.symbol] ?? store.liveQuotes[tick.symbol] ?? store.data.quotes[tick.symbol]
            let quote = LiveProtocol.merge(previous, tick)
            if quote.isValid {
                buffer[tick.symbol] = quote; queueFlush()
                if let real = LiveProtocol.realTrade(quote, tick, known: lastReal[tick.symbol]) { lastReal[tick.symbol] = real }
            }
        case .error(let code, let message):
            failed(code: code, message: message)
        case .heartbeat, .other:
            break
        }
    }
    private func failed(code: Int, message: String) {
        if code == 1000 {
            keyRejected = true; note = "富果拒絕這把金鑰，請到「富果行情連線」重新確認。"; closeSocket()
        } else if code == 1003 || message.localizedCaseInsensitiveContains("maximum number of connections") {
            busy()
        } else if code == 1001 {
            cap = subs.count; pending = [:]; note = "已達即時訂閱上限，其餘改為定時更新。"
        }
        publish()
    }
    private func busy() {
        closeSocket()
        busyUntil = Date().addingTimeInterval(60)
        note = "同一把金鑰正在其他裝置即時連線，這裡先改為定時更新。"
    }
    private func socketEnded(_ task: URLSessionWebSocketTask) {
        let wasAuthed = authed
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        socket = nil; authed = false; subs = [:]; pending = [:]
        if task.closeCode.rawValue == 1013 || reason.localizedCaseInsensitiveContains("maximum number of connections") { busy(); publish(); return }
        if keyRejected { publish(); return }
        if !wasAuthed {
            fails += 1
            // Three connections in a row that never authenticated: rest for five minutes, polling meanwhile.
            if fails >= 3 { fails = 0; retry = 0; reconnectAt = nil; pausedUntil = Date().addingTimeInterval(300); note = Self.pausedNote; publish(); return }
        }
        scheduleReconnect()
    }
    private func scheduleReconnect() {
        retry += 1
        reconnectAt = Date().addingTimeInterval(LiveProtocol.backoff(attempt: retry))
        publish()
    }
    private func closeSocket() {
        generation += 1
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil; authed = false; subs = [:]; pending = [:]
    }
    /// Symbols to keep fresh, most important first: the open detail page, holdings by value, then the watchlist.
    private func targets() -> [String] {
        var out: [String] = [], seen = Set<String>()
        func add(_ symbol: String?) { if let symbol, DataChecks.code(symbol), seen.insert(symbol).inserted { out.append(symbol) } }
        add(store.liveFocus)
        let holdings = store.data.holdings.sorted { (store.marketValue(of: $0) ?? 0) > (store.marketValue(of: $1) ?? 0) }
        for holding in holdings { add(holding.symbol) }
        for symbol in store.data.favorites.sorted() { add(symbol) }
        return out
    }
    /// Unsubscribe what is no longer wanted (by the ids the server returned), subscribe what is missing.
    private func sync() {
        guard let socket, authed else { publish(); return }
        let now = Date()
        pending = pending.filter { now.timeIntervalSince($0.value) < 10 }
        let want = Array(targets().prefix(limit))
        let drop = subs.filter { !want.contains($0.key) }
        if !drop.isEmpty {
            send(LiveProtocol.unsubscribe(Array(drop.values)), on: socket)
            for symbol in drop.keys { subs[symbol] = nil }
        }
        let room = max(0, limit - subs.count - pending.count)
        let add = Array(want.filter { subs[$0] == nil && pending[$0] == nil }.prefix(room))
        if !add.isEmpty {
            for symbol in add { pending[symbol] = now }
            send(LiveProtocol.subscribe(add), on: socket)
        }
        publish()
    }

    /* ---------- REST ---------- */
    private func request(_ path: String, _ symbol: String, query: String = "") async throws -> Data {
        guard symbol.range(of: "^[0-9A-Z]{3,8}$", options: .regularExpression) != nil, let url = URL(string: "https://api.fugle.tw/marketdata/v1.0/stock/\(path)/\(symbol)\(query)") else { throw StoreError.invalidQuote }
        return try await PublicHTTP.get(url, key: apiKey)
    }
    private func quote(_ symbol: String) async throws -> Quote {
        var value = try Fugle.decode(await request("intraday/quote", symbol), expectedSymbol: symbol)
        value.currency = store.data.quotes[symbol]?.currency ?? LiveProtocol.guessCurrency(symbol)
        return value
    }
    private func snapshot() async throws -> [String: Quote] {
        var out: [String: Quote] = [:]
        for market in ["TSE", "OTC"] {
            let bytes = try await request("snapshot/quotes", market, query: "?type=ALLBUT0999")
            guard let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], let rows = root["data"] as? [[String: Any]] else { continue }
            let day = (root["date"] as? String) ?? DataChecks.day()
            for row in rows {
                guard let symbol = row["symbol"] as? String, DataChecks.code(symbol) else { continue }
                var fields = row
                if fields["date"] == nil { fields["date"] = day }
                if let total = row["tradeVolume"] { fields["total"] = ["tradeVolume": total] }
                guard let tick = LiveProtocol.tick(fields) else { continue }
                let quote = LiveProtocol.merge(store.data.quotes[symbol], tick)
                if quote.isValid {
                    out[symbol] = quote
                    if let real = LiveProtocol.realTrade(quote, tick, known: lastReal[symbol]) { lastReal[symbol] = real }
                }
            }
        }
        return out
    }
    private func streamedRecently(_ symbol: String) -> Bool {
        guard subs[symbol] != nil, let current = buffer[symbol] ?? store.liveQuotes[symbol] else { return false }
        return Date().timeIntervalSince(current.fetchedAt) < 6
    }
    private func pollIndices() async {
        for (name, symbol) in [("taiex", "IX0001"), ("tpex", "IX0043")] {
            do { store.indices[name] = try Fugle.decode(await request("intraday/quote", symbol), expectedSymbol: symbol) }
            catch { if restFailed(error) { break } }
        }
        lastUpdate = Date(); publish()
    }
    /// Paid plans: the whole market every 5 s. Free plan: one quote per step, so a round stays near 40 requests a minute
    /// (the indices use 8 more), after first catching up the symbols the stream has not sent yet.
    private func poll() async {
        polling = true
        defer { polling = false }
        do {
            if paid != false {
                let quotes = try await snapshot()
                paid = true
                for (symbol, quote) in quotes where !streamedRecently(symbol) { buffer[symbol] = quote }
                pollAt = Date().addingTimeInterval(5)
                queueFlush()
                return
            }
            if !catchUp.isEmpty {
                let symbol = catchUp.removeFirst()
                let value = try await quote(symbol)
                if !streamedRecently(symbol) { buffer[symbol] = value; queueFlush() }
            if value.trial != true { lastReal[symbol] = value }
                pollAt = Date().addingTimeInterval(1.2)
                return
            }
            let rest = targets().filter { subs[$0] == nil }
            guard !rest.isEmpty else { pollSeconds = 0; pollAt = Date().addingTimeInterval(10); publish(); return }
            let cycle = max(10, Double(rest.count) * 60 / 40)
            pollSeconds = Int(cycle.rounded())
            let symbol = rest[pollIndex % rest.count]
            pollIndex += 1
            let value = try await quote(symbol)
            if !streamedRecently(symbol) { buffer[symbol] = value; queueFlush() }
            if value.trial != true { lastReal[symbol] = value }
            pollAt = Date().addingTimeInterval(max(1.5, cycle / Double(rest.count)))
        } catch {
            if let failure = error as? StoreError, case .http(let code) = failure, code == 403, paid != false {
                paid = false; pollAt = Date(); publish(); return
            }
            _ = restFailed(error)
            pollAt = Date().addingTimeInterval(15)
        }
    }
    /// Returns true when requests should stop for now.
    private func restFailed(_ error: Error) -> Bool {
        guard let failure = error as? StoreError, case .http(let code) = failure else { return false }
        if code == 429 { backoffUntil = Date().addingTimeInterval(60); note = "報價請求次數已達上限，1 分鐘後再更新。"; publish(); return true }
        if code == 401 { keyRejected = true; closeSocket(); note = "金鑰無效或已失效，請重新確認。"; publish(); return true }
        return false
    }

    /* ---------- publishing ---------- */
    /// Prices reach the screen at most every 0.7 s.
    private func queueFlush() {
        guard !flushQueued else { return }
        flushQueued = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.flush()
        }
    }
    private func flush() {
        flushQueued = false
        guard !buffer.isEmpty else { return }
        var next = store.liveQuotes
        for (symbol, quote) in buffer { next[symbol] = quote }
        buffer = [:]
        store.liveQuotes = next
        lastUpdate = Date()
        publish()
    }
    private func publish() {
        var status = LiveStatus()
        status.running = wanted
        status.marketOpen = TaiwanMarket.isOpen()
        status.connecting = socket != nil && !authed
        status.reconnecting = socket == nil && reconnectAt != nil
        status.subscribed = Set(subs.keys)
        status.pollSeconds = pollSeconds
        status.paidPlan = paid == true
        status.hasKey = !apiKey.isEmpty
        status.note = note
        status.lastUpdate = lastUpdate
        if store.liveStatus != status { store.liveStatus = status }
    }
    /// Saves the latest streamed prices of holdings and watchlist, so the next launch starts from them.
    private func keepLastPrices() {
        flush()
        let keep = Set(store.data.holdings.map(\.symbol)).union(store.data.favorites)
        var next = store.data
        var changed = false
        for symbol in keep {
            // A trial-match price is not a trade, so the last real one is saved instead.
            guard let live = store.liveQuotes[symbol], let quote = live.trial == true ? lastReal[symbol] : live, quote.isValid,
                  (next.quotes[symbol]?.fetchedAt ?? .distantPast) < quote.fetchedAt else { continue }
            next.quotes[symbol] = quote
            changed = true
        }
        if changed { try? store.commit(next) }
        // Trial-match prices are not shown once the feed stops: the saved real trade (or the last one seen) takes over.
        let shown = store.liveQuotes
        var kept = shown.filter { $0.value.trial != true }
        for (symbol, quote) in shown where quote.trial == true { if let real = lastReal[symbol], real.date == quote.date { kept[symbol] = real } }
        if kept.count != shown.count || shown.contains(where: { $0.value.trial == true }) { store.liveQuotes = kept }
    }
}
