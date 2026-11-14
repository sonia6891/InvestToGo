import Foundation

struct DailyBar: Codable, Equatable {
    var date: String   // yyyy-MM-dd
    var close: Double
}

struct DividendEvent: Codable, Equatable {
    var symbol: String
    var exDate: String
    var cash: Double
}

struct SplitEvent: Codable, Equatable {
    var symbol: String
    var resumeDate: String
    /// Shares after ÷ before (4 for 0050, 1/7 for 00632R).
    var ratio: Double
}

/// Parsers and URL builders for the TWSE / TPEx official history endpoints.
enum OfficialHistory {
    // MARK: Dates and numbers

    /// "114/06/18" or "114年01月17日" -> "2025-06-18"; nil when it isn't a ROC date.
    static func rocDate(_ s: String) -> String? {
        let parts = s.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet(charactersIn: "/年月日"))
            .filter { !$0.isEmpty }
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d), y > 0 else { return nil }
        return String(format: "%04d-%02d-%02d", y + 1911, m, d)
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppDataError("官方資料格式不符（不是 JSON 物件）")
        }
        return obj
    }

    private static func rows(_ any: [[Any]]) -> [[String]] {
        any.map { $0.map { ($0 as? String) ?? "\($0)" } }
    }

    /// Field name -> column index; all whitespace is removed from names ("日 期" -> "日期").
    private static func fieldIndexes(_ any: Any?) -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, f) in (any as? [String] ?? []).enumerated() {
            let key = f.components(separatedBy: .whitespacesAndNewlines).joined()
            if map[key] == nil { map[key] = i }
        }
        return map
    }

    /// TWSE bodies: `stat` must be OK; the 「沒有符合條件」 message means a genuinely empty result (nil).
    private static func twseTable(_ data: Data, what: String) throws -> [String: Any]? {
        let obj = try object(data)
        let stat = (obj["stat"] as? String) ?? ""
        if stat.contains("沒有符合條件") { return nil }
        guard stat.lowercased() == "ok" else {
            throw AppDataError("\(what)回應異常：\(stat.isEmpty ? "缺少 stat" : stat)")
        }
        return obj
    }

    private static func tpexTable(_ data: Data, what: String) throws -> [String: Any] {
        let obj = try object(data)
        guard let table = (obj["tables"] as? [[String: Any]])?.first else {
            throw AppDataError("\(what)資料格式不符（缺少 tables）")
        }
        return table
    }

    /// Shared row parsing: `data` must be an array; non-empty data needs every required field and at least one parsable row.
    private static func parseTable<T>(_ table: [String: Any], what: String, required: [String],
                                      row: ([String: Int], [String]) -> T?) throws -> [T] {
        guard let raw = table["data"] as? [[Any]] else {
            throw AppDataError("\(what)資料格式不符（缺少 data）")
        }
        if raw.isEmpty { return [] }
        let idx = fieldIndexes(table["fields"])
        if let missing = required.first(where: { idx[$0] == nil }) {
            throw AppDataError("\(what)資料欄位不符（缺少「\(missing)」）")
        }
        let out = rows(raw).compactMap { row(idx, $0) }
        if out.isEmpty { throw AppDataError("\(what)資料無法解析（\(raw.count) 列皆無效）") }
        return out
    }

    private static func barRow(_ dateKey: String, _ closeKey: String) -> ([String: Int], [String]) -> DailyBar? {
        { idx, r in
            guard let di = idx[dateKey], let ci = idx[closeKey], r.count > max(di, ci),
                  let date = rocDate(r[di]), let close = number(r[ci]), close > 0 else { return nil }
            return DailyBar(date: date, close: close)
        }
    }

    // MARK: Prices

    static func twseMonth(_ data: Data) throws -> [DailyBar] {
        guard let obj = try twseTable(data, what: "證交所日成交") else { return [] }
        return try parseTable(obj, what: "證交所日成交", required: ["日期", "收盤價"], row: barRow("日期", "收盤價"))
    }

    static func tpexMonth(_ data: Data) throws -> [DailyBar] {
        let table = try tpexTable(data, what: "櫃買日成交")
        return try parseTable(table, what: "櫃買日成交", required: ["日期", "收盤"], row: barRow("日期", "收盤"))
    }

    // MARK: Dividends

    static func twseDividends(_ data: Data) throws -> [DividendEvent] {
        guard let obj = try twseTable(data, what: "證交所除權息") else { return [] }
        let req = ["資料日期", "股票代號", "權值+息值", "權/息"]
        let all: [DividendEvent?] = try parseTable(obj, what: "證交所除權息", required: req) { idx, r in
            let di = idx["資料日期"]!, si = idx["股票代號"]!, ci = idx["權值+息值"]!, ki = idx["權/息"]!
            guard r.count > max(di, si, ci, ki), let date = rocDate(r[di]), let cash = number(r[ci]) else { return nil }
            // 權 rows parse fine but are not cash dividends; keep a nil marker so they don't count as unparsable.
            guard r[ki].trimmingCharacters(in: .whitespaces) == "息" else { return .some(nil) }
            return .some(DividendEvent(symbol: r[si].trimmingCharacters(in: .whitespaces), exDate: date, cash: cash))
        }
        return all.compactMap { $0 }
    }

    static func tpexDividends(_ data: Data) throws -> [DividendEvent] {
        let table = try tpexTable(data, what: "櫃買除權息")
        let count = (table["fields"] as? [Any])?.count ?? 0
        return try parseTable(table, what: "櫃買除權息", required: ["除權息日期", "代號", "現金股利"]) { idx, r in
            let di = idx["除權息日期"]!, si = idx["代號"]!, ci = idx["現金股利"]!
            guard r.count == count, let date = rocDate(r[di]), let cash = number(r[ci]) else { return nil }
            return DividendEvent(symbol: r[si].trimmingCharacters(in: .whitespaces), exDate: date, cash: cash)
        }
    }

    // MARK: Splits

    static func splits(_ data: Data) throws -> [SplitEvent] {
        guard let obj = try twseTable(data, what: "ETF 分割") else { return [] }
        let req = ["恢復買賣日期", "ETF代號", "停止買賣前收盤價格", "恢復買賣參考價"]
        return try parseTable(obj, what: "ETF 分割", required: req) { idx, r in
            let di = idx["恢復買賣日期"]!, si = idx["ETF代號"]!, bi = idx["停止買賣前收盤價格"]!, ai = idx["恢復買賣參考價"]!
            guard r.count > max(di, si, bi, ai), let date = rocDate(r[di]),
                  let before = number(r[bi]), let after = number(r[ai]), before > 0, after > 0 else { return nil }
            let x = before / after
            let ratio = x >= 1 ? x.rounded() : 1 / (1 / x).rounded()
            return SplitEvent(symbol: r[si].trimmingCharacters(in: .whitespaces), resumeDate: date, ratio: ratio)
        }
    }

    /// Dates where the close jumps by more than ×2.5 or below ×0.4 with no dividend and no known split that day.
    static func suspectedSplits(_ bars: [DailyBar], dividends: [DividendEvent], known: [SplitEvent]) -> [String] {
        let explained = Set(dividends.map(\.exDate)).union(known.map(\.resumeDate))
        var out: [String] = []
        for i in bars.indices.dropFirst() {
            let prev = bars[i - 1].close
            guard prev > 0 else { continue }
            let r = bars[i].close / prev
            if (r > 2.5 || r < 0.4) && !explained.contains(bars[i].date) { out.append(bars[i].date) }
        }
        return out
    }

    // MARK: URLs

    private static func ymd(_ date: Date, separator: String) -> String {
        let c = GameRules.taipei.dateComponents([.year, .month, .day], from: date)
        let y = String(format: "%04d", c.year ?? 1970)
        let m = String(format: "%02d", c.month ?? 1)
        let d = String(format: "%02d", c.day ?? 1)
        return [y, m, d].joined(separator: separator)
    }

    static func twseMonthURL(symbol: String, month: YearMonth) -> URL {
        let ym = String(format: "%04d%02d", month.year, month.month)
        return URL(string: "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=\(ym)01&stockNo=\(symbol)&response=json")!
    }

    static func tpexMonthURL(symbol: String, month: YearMonth) -> URL {
        let ym = String(format: "%04d/%02d", month.year, month.month)
        return URL(string: "https://www.tpex.org.tw/www/zh-tw/afterTrading/tradingStock?code=\(symbol)&date=\(ym)/01&response=json")!
    }

    static func twseDividendsURL(from: Date, to: Date) -> URL {
        URL(string: "https://www.twse.com.tw/rwd/zh/exRight/TWT49U?startDate=\(ymd(from, separator: ""))&endDate=\(ymd(to, separator: ""))&response=json")!
    }

    static func tpexDividendsURL(from: Date, to: Date) -> URL {
        URL(string: "https://www.tpex.org.tw/www/zh-tw/bulletin/exDailyQ?startDate=\(ymd(from, separator: "/"))&endDate=\(ymd(to, separator: "/"))&response=json")!
    }

    static func splitsURL(from: Date, to: Date) -> URL {
        URL(string: "https://www.twse.com.tw/rwd/zh/split/TWTCAU?startDate=\(ymd(from, separator: ""))&endDate=\(ymd(to, separator: ""))&response=json")!
    }
}
