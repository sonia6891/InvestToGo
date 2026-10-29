import Foundation
@testable import ETFToGo

/// A small portfolio for unit tests (not part of the app).
extension Portfolio {
    static var sample: Portfolio {
        var value = Portfolio()
        value.holdings = [
            .init(symbol: "0050", name: "元大台灣50", shares: 2000, unitCost: 50, broker: "富邦證券", strategy: .saving),
            .init(symbol: "00878", name: "國泰永續高股息", shares: 6000, unitCost: 20, broker: "富邦證券", strategy: .income),
            .init(symbol: "00919", name: "群益台灣精選高息", shares: 5000, unitCost: 22, broker: "國泰證券", strategy: .income)
        ]
        let prices: [String: Double] = ["0050": 55, "00878": 21, "00919": 22.5]
        for (symbol, price) in prices { value.quotes[symbol] = Quote(symbol: symbol, price: price, changePercent: 0.42, date: DataChecks.day(), fetchedAt: Date()) }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        value.dividends = [
            Dividend(symbol: "00878", date: Calendar.current.date(byAdding: .day, value: 7, to: start)!, amount: 2400, status: .paid),
            Dividend(symbol: "00919", date: Calendar.current.date(byAdding: .day, value: 19, to: start)!, amount: 3600, status: .announced)
        ]
        value.favorites = ["0050", "00878", "00919"]
        return value
    }
}
