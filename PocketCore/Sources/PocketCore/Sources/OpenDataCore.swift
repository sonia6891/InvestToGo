import Foundation

/// Each trading day's prices from the exchanges' open data, released after the close under the 政府資料開放授權條款
/// (free to use, with the attribution on the About page): TWSE 上市個股日成交資訊 and 每日收盤行情 (TAIEX), TPEx 上櫃股票
/// 收盤行情 and 櫃買指數. Intraday prices come only from the user's own Fugle key.
enum OpenData {
    static let source = "收盤"
    /// One trading day's figures, cached on the device.
    struct Day: Codable {
        var quotes: [String: Quote]
        var indices: [String: Quote]
        var fetchedAt: Date
        /// The latest trading day in the data (TWSE and TPEx may be a day apart while one has not published yet).
        var day: String { (Array(quotes.values) + Array(indices.values)).map(\.date).max() ?? "" }
        /// The older of the two exchanges' latest days, by their indices: TWSE's open data can lag TPEx's by a day or
        /// more. An index that did not decode does not count, or the closes would look behind forever.
        var settledDay: String { ["taiex", "tpex"].compactMap { indices[$0]?.date }.min() ?? day }
    }
    static let twseQuotes = URL(string: "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL")!
    static let twseIndices = URL(string: "https://openapi.twse.com.tw/v1/exchangeReport/MI_INDEX")!
    static let tpexQuotes = URL(string: "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes")!
    static let tpexIndex = URL(string: "https://www.tpex.org.tw/openapi/v1/tpex_index")!

    /// Both exchanges; one side failing still returns the other.
    private static func rows(_ bytes: Data) throws -> [[String: Any]] {
        guard let rows = DataChecks.jsonRows(bytes) else { throw StoreError.invalidQuote }
        return rows
    }
    private static func number(_ value: Any?) -> Double? {
        guard let text = (value as? String)?.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces),
              let parsed = Double(text), parsed.isFinite else { return nil }
        return parsed
    }
    /// The close is fixed at 13:30 Taipei on its trading day, so a newer live quote always wins over it.
    private static func quote(_ code: String, day: String, close: Double, change: Double?, open: Double?, high: Double?, low: Double?, shares: Double?) -> Quote? {
        guard close > 0, let midnight = DataChecks.date(day) else { return nil }
        let previous = change.map { close - $0 }
        let percent: Double? = previous.flatMap { $0 > 0 ? ((close - $0) / $0 * 10000).rounded() / 100 : nil }
        var value = Quote(symbol: code, price: close, changePercent: percent, date: day, fetchedAt: midnight.addingTimeInterval(13.5 * 3600),
                          currency: code.hasSuffix("K") || code.hasSuffix("C") ? "UNKNOWN" : "TWD", change: change, open: open, high: high, low: low,
                          volume: shares.map { ($0 / 1000).rounded() }, source: source)
        if !value.isValid { value.open = nil; value.high = nil; value.low = nil; value.volume = nil }
        return value.isValid ? value : nil
    }
    /// 上市個股日成交資訊: Code, Date (ROC), OpeningPrice … ClosingPrice, Change, TradeVolume (shares).
    static func decodeTWSE(_ bytes: Data) throws -> [String: Quote] {
        var result: [String: Quote] = [:]
        for row in try rows(bytes) {
            guard let code = row["Code"] as? String, DataChecks.code(code), let day = DataChecks.rocDay((row["Date"] as? String) ?? ""),
                  let close = number(row["ClosingPrice"]) else { continue }
            if let value = quote(code, day: day, close: close, change: number(row["Change"]), open: number(row["OpeningPrice"]),
                                 high: number(row["HighestPrice"]), low: number(row["LowestPrice"]), shares: number(row["TradeVolume"])) { result[code] = value }
        }
        return result
    }
    /// 上櫃股票收盤行情: SecuritiesCompanyCode, Date (ROC), Open … Close, Change (signed), TradingShares.
    static func decodeTPEx(_ bytes: Data) throws -> [String: Quote] {
        var result: [String: Quote] = [:]
        for row in try rows(bytes) {
            guard let code = (row["SecuritiesCompanyCode"] as? String)?.trimmingCharacters(in: .whitespaces), DataChecks.code(code),
                  let day = DataChecks.rocDay((row["Date"] as? String) ?? ""), let close = number(row["Close"]) else { continue }
            if let value = quote(code, day: day, close: close, change: number(row["Change"]), open: number(row["Open"]),
                                 high: number(row["High"]), low: number(row["Low"]), shares: number(row["TradingShares"])) { result[code] = value }
        }
        return result
    }
    /// 每日收盤行情－大盤統計資訊: the 發行量加權股價指數 row; 漲跌 holds the sign and 漲跌點數 the size.
    static func decodeTAIEX(_ bytes: Data) throws -> Quote? {
        guard let row = try rows(bytes).first(where: { ($0["指數"] as? String) == "發行量加權股價指數" }),
              let day = DataChecks.rocDay((row["日期"] as? String) ?? ""), let close = number(row["收盤指數"]) else { return nil }
        let size = number(row["漲跌點數"]), sign = ((row["漲跌"] as? String) ?? "").contains("-") ? -1.0 : 1.0
        return quote("IX0001", day: day, close: close, change: size.map { $0 * sign }, open: nil, high: nil, low: nil, shares: nil)
    }
    /// 櫃買指數歷史資料: the latest row; Date is yyyyMMdd and Change is signed.
    static func decodeTPExIndex(_ bytes: Data) throws -> Quote? {
        let dated = try rows(bytes).compactMap { row -> (String, [String: Any])? in
            guard let raw = row["Date"] as? String, raw.count == 8 else { return nil }
            return ("\(raw.prefix(4))-\(raw.dropFirst(4).prefix(2))-\(raw.suffix(2))", row)
        }
        guard let latest = dated.max(by: { $0.0 < $1.0 }), let close = number(latest.1["Close"]) else { return nil }
        let row = latest.1
        return quote("IX0043", day: latest.0, close: close, change: number(row["Change"]), open: number(row["Open"]), high: number(row["High"]), low: number(row["Low"]), shares: nil)
    }
    /// The trading day whose close should be out by now: today after 14:30 on a weekday, else the weekday before.
    static func expectedDay(_ now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TaiwanMarket.zone
        var date = now
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        if (parts.hour ?? 0) * 60 + (parts.minute ?? 0) < 14 * 60 + 30 { date = calendar.date(byAdding: .day, value: -1, to: date) ?? date }
        while [1, 7].contains(calendar.component(.weekday, from: date)) { date = calendar.date(byAdding: .day, value: -1, to: date) ?? date }
        return DataChecks.day(date)
    }
}
