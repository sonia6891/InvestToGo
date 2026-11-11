import Foundation

/// Parses Fugle market-data responses. Network calls (which need the user's key) stay in the app.
public enum FugleDecode {
    struct QuoteResponse: Decodable { let symbol: String; let date: String; let closePrice: Double?; let lastPrice: Double?; let changePercent: Double? }

    public static func quote(_ bytes: Data, expectedSymbol: String) throws -> Quote {
        let value = try JSONDecoder().decode(QuoteResponse.self, from: bytes)
        guard value.symbol == expectedSymbol, let price = value.closePrice ?? value.lastPrice, price.isFinite, price > 0 else { throw StoreError.invalidQuote }
        return Quote(symbol: value.symbol, price: price, changePercent: value.changePercent, date: value.date, fetchedAt: Date())
    }

    public static func components(_ bytes: Data, symbol: String) throws -> ComponentSnapshot {
        struct Day: Decodable { var date: String; var components: [FundComponent] }
        struct Response: Decodable { var symbol: String; var data: [Day] }
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        guard response.symbol == symbol, let day = response.data.max(by: { $0.date < $1.date }), !day.components.isEmpty else { throw AppDataError("此區間沒有股票成分資料；債券、期貨或部分外幣級別可能沒有此資料，不能視為零重疊。") }
        let value = ComponentSnapshot(symbol: symbol, date: day.date, components: day.components, source: "富果／投信揭露資料")
        try value.validate(); return value
    }

    public static func history(_ bytes: Data, symbol: String) throws -> [PricePoint] {
        struct Response: Decodable { var symbol: String; var adjusted: Bool?; var timeframe: String; var data: [PricePoint] }
        let value = try JSONDecoder().decode(Response.self, from: bytes)
        guard value.symbol == symbol, value.adjusted == true, value.timeframe == "D" else { throw AppDataError("行情服務未確認還原價格，未計算績效。") }
        return value.data
    }
}
