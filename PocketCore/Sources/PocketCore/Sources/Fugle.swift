import Foundation

enum Fugle {
    struct Total: Decodable { let tradeVolume: Double? }
    struct Response: Decodable { let symbol: String; let date: String; let closePrice: Double?; let lastPrice: Double?; let changePercent: Double?; let change: Double?; let openPrice: Double?; let highPrice: Double?; let lowPrice: Double?; let total: Total?; let isTrial: Bool? }
    static func decode(_ bytes: Data, expectedSymbol: String) throws -> Quote {
        let value = try JSONDecoder().decode(Response.self, from: bytes)
        // During a trial match only lastPrice moves (closePrice is the last real trade), as in the stream.
        let trial = value.isTrial == true
        guard value.symbol == expectedSymbol, let price = trial ? (value.lastPrice ?? value.closePrice) : (value.closePrice ?? value.lastPrice), price.isFinite, price > 0 else { throw StoreError.invalidQuote }
        let quote = Quote(symbol: value.symbol, price: price, changePercent: value.changePercent, date: value.date, fetchedAt: Date(), change: value.change, open: value.openPrice, high: value.highPrice, low: value.lowPrice, volume: value.total?.tradeVolume, trial: trial ? true : nil)
        guard quote.isValid else { throw StoreError.invalidQuote }
        return quote
    }
}
