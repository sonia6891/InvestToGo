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

    private static func rows(_ any: Any?) -> [[String]] {
        (any as? [[Any]] ?? []).map { $0.map { ($0 as? String) ?? "\($0)" } }
    }

    private static func fieldIndexes(_ any: Any?) -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, f) in (any as? [String] ?? []).enumerated() {
            let key = f.trimmingCharacters(in: .whitespaces)
            if map[key] == nil { map[key] = i }
        }
        return map
    }

    private static func bars(_ rows: [[String]]) -> [DailyBar] {
        rows.compactMap { r in
            guard r.count > 6, let date = rocDate(r[0]), let close = number(r[6]), close > 0 else { return nil }
            return DailyBar(date: date, close: close)
        }
    }

    // MARK: Prices

    static func twseMonth(_ data: Data) throws -> [DailyBar] {
        let obj = try object(data)
        // 「很抱歉，沒有符合條件的資料!」 comes back without a data array.
        guard obj["data"] != nil else { return [] }
        return bars(rows(obj["data"]))
    }

    static func tpexMonth(_ data: Data) throws -> [DailyBar] {
        let obj = try object(data)
        guard let table = (obj["tables"] as? [[String: Any]])?.first else {
            throw AppDataError("櫃買資料格式不符（缺少 tables）")
        }
        return bars(rows(table["data"]))
    }

    // MARK: Dividends

    static func twseDividends(_ data: Data) throws -> [DividendEvent] {
        let obj = try object(data)
        let idx = fieldIndexes(obj["fields"])
        guard let di = idx["資料日期"], let si = idx["股票代號"], let ci = idx["權值+息值"], let ki = idx["權/息"] else {
            if obj["data"] == nil { return [] }
            throw AppDataError("證交所除權息資料欄位不符")
        }
        return rows(obj["data"]).compactMap { r in
            guard r.count > max(di, si, ci, ki),
                  r[ki].trimmingCharacters(in: .whitespaces) == "息",
                  let date = rocDate(r[di]), let cash = number(r[ci]) else { return nil }
            return DividendEvent(symbol: r[si].trimmingCharacters(in: .whitespaces), exDate: date, cash: cash)
        }
    }

    static func tpexDividends(_ data: Data) throws -> [DividendEvent] {
        let obj = try object(data)
        guard let table = (obj["tables"] as? [[String: Any]])?.first else {
            throw AppDataError("櫃買除權息資料格式不符（缺少 tables）")
        }
        let idx = fieldIndexes(table["fields"])
        let count = (table["fields"] as? [Any])?.count ?? 0
        guard let di = idx["除權息日期"], let si = idx["代號"], let ci = idx["現金股利"] else {
            if table["data"] == nil { return [] }
            throw AppDataError("櫃買除權息資料欄位不符")
        }
        return rows(table["data"]).compactMap { r in
            guard r.count == count, let date = rocDate(r[di]), let cash = number(r[ci]) else { return nil }
            return DividendEvent(symbol: r[si].trimmingCharacters(in: .whitespaces), exDate: date, cash: cash)
        }
    }

    // MARK: Splits

    static func splits(_ data: Data) throws -> [SplitEvent] {
        let obj = try object(data)
        let idx = fieldIndexes(obj["fields"])
        guard let di = idx["恢復買賣日期"], let si = idx["ETF代號"],
              let bi = idx["停止買賣前收盤價格"], let ai = idx["恢復買賣參考價"] else {
            if obj["data"] == nil { return [] }
            throw AppDataError("ETF 分割資料欄位不符")
        }
        return rows(obj["data"]).compactMap { r in
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
