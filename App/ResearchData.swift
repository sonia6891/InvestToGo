import Foundation
import PocketCore

extension Fugle {
    static func data(path: String, symbol: String, query: [URLQueryItem] = []) async throws -> Data {
        guard DataChecks.code(symbol) else { throw StoreError.invalidQuote }
        let key = try SecureKey.read(); guard !key.isEmpty else { throw StoreError.missingKey }
        var url = URLComponents(string: "https://api.fugle.tw/marketdata/v1.0/stock/\(path)/\(symbol)")!; url.queryItems = query.isEmpty ? nil : query
        return try await PublicHTTP.get(url.url!, key: key)
    }
    static func components(symbol: String) async throws -> ComponentSnapshot {
        try FugleDecode.components(await data(path: "ownership/etf-holdings", symbol: symbol), symbol: symbol)
    }
    static func history(symbol: String, years: Int) async throws -> PriceHistory {
        guard [1,3,5,10,16].contains(years) else { throw AppDataError("不支援此查詢區間。") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let end = DataChecks.date(DataChecks.day())!
        let earliest = DataChecks.date("2010-01-01")!
        var cursor = max(calendar.date(byAdding: .year, value: -years, to: end)!, earliest)
        var points: [PricePoint] = []
        while cursor <= end {
            try Task.checkCancellation()
            let chunkEnd = min(calendar.date(byAdding: .day, value: 359, to: cursor)!, end)
            do {
                let bytes = try await data(path: "historical/candles", symbol: symbol, query: [URLQueryItem(name: "from", value: DataChecks.day(cursor)), URLQueryItem(name: "to", value: DataChecks.day(chunkEnd)), URLQueryItem(name: "timeframe", value: "D"), URLQueryItem(name: "adjusted", value: "true"), URLQueryItem(name: "fields", value: "close"), URLQueryItem(name: "sort", value: "asc")])
                let chunk = try FugleDecode.history(bytes, symbol: symbol)
                guard chunk.allSatisfy({ $0.date >= DataChecks.day(cursor) && $0.date <= DataChecks.day(chunkEnd) }) else { throw AppDataError("歷史回傳日期超出查詢區間。") }
                points.append(contentsOf: chunk)
            } catch StoreError.http(404) { /* Pre-listing/non-trading intervals may legitimately contain no data. */ }
            cursor = calendar.date(byAdding: .day, value: 1, to: chunkEnd)!
            if cursor <= end { try await Task.sleep(nanoseconds: 1_100_000_000) }
        }
        let history = PriceHistory(symbol: symbol, adjusted: true, points: points.sorted { $0.date < $1.date }, fetchedDay: DataChecks.day(), source: "富果還原日收盤價")
        try history.validate(); return history
    }
}
