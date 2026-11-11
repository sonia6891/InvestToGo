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

    /// Replaces a quote only with a strictly newer trading date, so a fresher intraday quote is never overwritten.
    public static func merge(_ incoming: [Quote], into existing: [String: Quote]) -> [String: Quote] {
        var result = existing
        for quote in incoming where result[quote.symbol].map({ quote.date > $0.date }) ?? true { result[quote.symbol] = quote }
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
