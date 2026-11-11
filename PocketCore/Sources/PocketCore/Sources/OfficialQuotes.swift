import Foundation

/// Free, key-less after-hours closing prices published by TWSE and TPEx open data.
public enum OfficialQuotes {
    public static let source = "證交所／櫃買中心盤後收盤價"
    public static let twseURL = "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"
    public static let tpexURL = "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes"

    public static func decodeTWSE(_ bytes: Data, fetchedAt: Date) throws -> [Quote] {
        try JSONDecoder().decode([[String: String]].self, from: bytes)
            .compactMap { try quote(code: $0["Code"], close: $0["ClosingPrice"], rocDate: $0["Date"], fetchedAt: fetchedAt) }
    }

    public static func decodeTPEx(_ bytes: Data, fetchedAt: Date) throws -> [Quote] {
        try JSONDecoder().decode([[String: String]].self, from: bytes)
            .compactMap { try quote(code: $0["SecuritiesCompanyCode"], close: $0["Close"], rocDate: $0["Date"], fetchedAt: fetchedAt) }
    }

    /// Seconds after midnight (Asia/Taipei) by which the official close for that day is final: 14:30.
    static let closeFinalAfter: TimeInterval = 14.5 * 3600

    /// Takes the official close when it is for a newer trading day, or for the same day as a quote fetched mid-session;
    /// an older close, or a same-day quote fetched after the close, is kept.
    public static func merge(_ incoming: [Quote], into existing: [String: Quote]) -> [String: Quote] {
        var result = existing
        for quote in incoming {
            guard let current = result[quote.symbol] else { result[quote.symbol] = quote; continue }
            let fetchedMidSession = DataChecks.date(current.date).map { current.fetchedAt < $0.addingTimeInterval(closeFinalAfter) } ?? false
            if quote.date > current.date || (quote.date == current.date && fetchedMidSession) { result[quote.symbol] = quote }
        }
        return result
    }

    private static func quote(code: String?, close: String?, rocDate: String?, fetchedAt: Date) throws -> Quote? {
        guard let code = code?.trimmingCharacters(in: .whitespaces), code.hasPrefix("00"), DataChecks.code(code) else { return nil }
        guard let raw = rocDate, raw.allSatisfy(\.isNumber), let day = DataChecks.rocDay(raw) else { throw AppDataError("官方收盤價日期格式改變，保留原有報價。") }
        guard let text = close?.trimmingCharacters(in: .whitespaces), let price = Double(text), price.isFinite, price > 0 else { return nil }
        // K and C suffixes are foreign-currency share classes; U is a TWD-traded futures ETF.
        let currency = code.hasSuffix("K") || code.hasSuffix("C") ? "UNKNOWN" : "TWD"
        return Quote(symbol: code, price: price, changePercent: nil, date: day, fetchedAt: fetchedAt, currency: currency)
    }
}
