import Foundation
@testable import PocketCore

/// A quote as vector output; `fetchedAt` only where it is fixed by the data (the close is stamped at 13:30).
func quoteOutput(_ q: Quote, fetchedAt: Bool) -> [String: Any] {
    var out: [String: Any] = [
        "symbol": q.symbol, "price": q.price, "changePercent": orNull(q.changePercent), "date": q.date, "currency": orNull(q.currency),
        "change": orNull(q.change), "open": orNull(q.open), "high": orNull(q.high), "low": orNull(q.low), "volume": orNull(q.volume),
        "source": orNull(q.source), "trial": orNull(q.trial),
    ]
    if fetchedAt { out["fetchedAt"] = q.fetchedAt.timeIntervalSince1970 }
    return out
}

func shortQuotes(_ quotes: [String: Quote]) -> [[String: Any]] {
    quotes.values.sorted { $0.symbol < $1.symbol }.map { ["symbol": $0.symbol, "price": $0.price, "date": $0.date, "currency": orNull($0.currency)] }
}

func snapshotOutput(_ s: ComponentSnapshot) -> [String: Any] {
    ["symbol": s.symbol, "date": s.date, "source": orNull(s.source),
     "components": s.components.map { ["symbol": $0.symbol, "name": orNull($0.name), "weight": $0.weight] as [String: Any] }]
}

func distributionOutput(_ d: OfficialDistribution) -> [String: Any] { ["ex": d.ex, "pay": d.pay, "amount": orNull(d.amount)] }

func dividendsOutput(_ r: OfficialDividends) -> [String: Any] {
    ["sources": r.sources, "events": r.events.mapValues { $0.map(distributionOutput) }, "freq": r.freq]
}

func fundOutput(_ f: Fund) -> [String: Any] {
    ["id": f.id, "name": f.name, "strategy": f.strategy.rawValue, "market": orNull(f.market), "fullName": orNull(f.fullName),
     "fundType": orNull(f.fundType), "listingDate": orNull(f.listingDate)]
}

func expenseOutput(_ e: AnnualExpense) -> [String: Any] {
    ["symbol": e.symbol, "fundID": e.fundID, "fundName": e.fundName, "year": e.year, "commission": e.commission, "tax": e.tax,
     "subscriptionOffset": e.subscriptionOffset, "management": e.management, "custody": e.custody, "guarantee": e.guarantee,
     "other": e.other, "total": e.total]
}

func optionalString(_ input: Any, _ key: String) throws -> String? { try VectorIO.object(input)[key] as? String }

func dividendRecord(_ input: Any) throws -> OfficialDividends { try VectorIO.decode(OfficialDividends.self, try value(input, "record")) }

func htmlInput(_ input: Any) throws -> String { String(decoding: try inputBytes(input), as: UTF8.self) }

let sourceHandlers: [String: VectorHandler] = [
    // OpenData
    "OpenData.decodeTWSE": { input in shortQuotes(try OpenData.decodeTWSE(inputBytes(input))) },
    "OpenData.decodeTPEx": { input in shortQuotes(try OpenData.decodeTPEx(inputBytes(input))) },
    "OpenData.quotes": { input in
        let all = try OpenData.decodeTWSE(Fixtures.data(string(input, "twse")))
            .merging(OpenData.decodeTPEx(Fixtures.data(string(input, "tpex")))) { first, _ in first }
        return all.mapValues { quoteOutput($0, fetchedAt: true) }
    },
    "OpenData.decodeTAIEX": { input in orNull(try OpenData.decodeTAIEX(inputBytes(input)).map { quoteOutput($0, fetchedAt: true) }) },
    "OpenData.decodeTPExIndex": { input in orNull(try OpenData.decodeTPExIndex(inputBytes(input)).map { quoteOutput($0, fetchedAt: true) }) },
    "OpenData.expectedDay": { input in OpenData.expectedDay(try at(input)) },
    // OfficialDividends
    "OfficialDividends.decode": { input in
        let markets = try VectorIO.decode([String: String].self, try value(input, "markets"))
        return try OfficialDividends.decode(inputBytes(input), market: string(input, "market"), markets: markets).mapValues { $0.map(distributionOutput) }
    },
    "OfficialDividends.rocDay": { input in orNull(OfficialDividends.rocDay(try string(input, "text"))) },
    "OfficialDividends.frequency(of:)": { input in
        orNull(OfficialDividends.frequency(of: try VectorIO.decode([OfficialDistribution].self, try value(input, "list")), now: try at(input, "now")))
    },
    "OfficialDividends.merging": { input in
        let fresh = try VectorIO.decode([String: [OfficialDistribution]].self, try value(input, "fresh"))
        let flag = (try VectorIO.object(input)["frequency"] as? Bool) ?? false
        return dividendsOutput(try dividendRecord(input).merging(fresh, frequency: flag, now: try at(input, "now")))
    },
    "OfficialDividends.trailingAmount": { input in orNull(try dividendRecord(input).trailingAmount(try string(input, "symbol"), now: try at(input, "now"))) },
    "OfficialDividends.isNewer": { input in
        let a = try VectorIO.decode([String: String].self, try value(input, "a")), b = try VectorIO.decode([String: String].self, try value(input, "b"))
        return OfficialDividends(sources: a).isNewer(than: OfficialDividends(sources: b))
    },
    "OfficialDividends.bundled.summary": { _ in
        let r = OfficialDividends.bundled()
        return ["sources": r.sources, "symbolCount": r.events.count, "firstSymbols": Array(r.events.keys.sorted().prefix(5)),
                "eventCount": r.events.values.reduce(0) { $0 + $1.count }, "freqCount": r.freq.count]
    },
    // Catalog and fees
    "CatalogAPI.strategy": { input in CatalogAPI.strategy(try string(input, "name")).rawValue },
    "CatalogAPI.unescape": { input in CatalogAPI.unescape(try string(input, "text")) },
    "CatalogAPI.decode": { input in
        let object = try VectorIO.object(input)
        let previous = try object["previous"].map { try VectorIO.decode(CatalogSnapshot.self, $0) }
        let s = try CatalogAPI.decode(listed: inputBytes(value(input, "listed")), twse: inputBytes(value(input, "twse")), otc: inputBytes(value(input, "otc")),
                                      previous: previous, today: string(input, "today"))
        return ["funds": s.funds.map(fundOutput), "listedDate": s.listedDate, "fetchedDay": s.fetchedDay, "sources": s.sources] as [String: Any]
    },
    "CatalogSnapshot.bundled.summary": { _ in
        orNull(CatalogSnapshot.bundled().map { ["count": $0.funds.count, "listedDate": $0.listedDate, "first": Array($0.funds.prefix(5).map(\.id))] as [String: Any] })
    },
    "AnnualFeeCatalog.bundled.summary": { _ in
        orNull(AnnualFeeCatalog.bundled.map { c -> [String: Any] in
            let first = c.records.keys.sorted().first.flatMap { c.records[$0] }
            return ["count": c.records.count, "fetchedDay": c.fetchedDay, "sourceURL": c.sourceURL, "first": orNull(first.map(expenseOutput))]
        })
    },
    // OfficialHistory
    "OfficialHistory.rocDate": { input in orNull(OfficialHistory.rocDate(try string(input, "text"))) },
    "OfficialHistory.twseMonth": { input in try OfficialHistory.twseMonth(inputBytes(input)).map { ["date": $0.date, "close": $0.close] } },
    "OfficialHistory.tpexMonth": { input in try OfficialHistory.tpexMonth(inputBytes(input)).map { ["date": $0.date, "close": $0.close] } },
    "OfficialHistory.twseDividends": { input in
        try OfficialHistory.twseDividends(inputBytes(input)).map { ["symbol": $0.symbol, "exDate": $0.exDate, "cash": $0.cash] as [String: Any] }
    },
    "OfficialHistory.tpexDividends": { input in
        try OfficialHistory.tpexDividends(inputBytes(input)).map { ["symbol": $0.symbol, "exDate": $0.exDate, "cash": $0.cash] as [String: Any] }
    },
    "OfficialHistory.splits": { input in
        try OfficialHistory.splits(inputBytes(input)).map { ["symbol": $0.symbol, "resumeDate": $0.resumeDate, "ratio": $0.ratio] as [String: Any] }
    },
    "OfficialHistory.suspectedSplits": { input in
        OfficialHistory.suspectedSplits(try VectorIO.decode([DailyBar].self, try value(input, "bars")),
                                        dividends: try VectorIO.decode([DividendEvent].self, try value(input, "dividends")),
                                        known: try VectorIO.decode([SplitEvent].self, try value(input, "known")))
    },
    "OfficialHistory.urls": { input in
        let symbol = try string(input, "symbol"), month = try VectorIO.decode(YearMonth.self, try value(input, "month"))
        let from = try at(input, "from"), to = try at(input, "to")
        return ["twseMonth": OfficialHistory.twseMonthURL(symbol: symbol, month: month).absoluteString,
                "tpexMonth": OfficialHistory.tpexMonthURL(symbol: symbol, month: month).absoluteString,
                "twseDividends": OfficialHistory.twseDividendsURL(from: from, to: to).absoluteString,
                "tpexDividends": OfficialHistory.tpexDividendsURL(from: from, to: to).absoluteString,
                "splits": OfficialHistory.splitsURL(from: from, to: to).absoluteString]
    },
    // Issuers
    "IssuerHoldings.yuanta": { input in snapshotOutput(try IssuerHoldings.yuanta(inputBytes(input), symbol: string(input, "symbol"))) },
    "IssuerHoldings.cathay": { input in snapshotOutput(try IssuerHoldings.cathay(inputBytes(input), symbol: string(input, "symbol"), date: string(input, "date"))) },
    "IssuerHoldings.fubon": { input in snapshotOutput(try IssuerHoldings.fubon(htmlInput(input), symbol: string(input, "symbol"))) },
    "IssuerHoldings.capital": { input in snapshotOutput(try IssuerHoldings.capital(inputBytes(input), symbol: string(input, "symbol"))) },
    "IssuerHoldings.fhtrust": { input in snapshotOutput(try IssuerHoldings.fhtrust(inputBytes(input), symbol: string(input, "symbol"))) },
    "IssuerHoldings.ctbc": { input in snapshotOutput(try IssuerHoldings.ctbc(inputBytes(input), symbol: string(input, "symbol"))) },
    "IssuerHoldings.day": { input in orNull(IssuerHoldings.day(try VectorIO.object(input)["value"])) },
    "IssuerHoldings.cathayFundCode": { input in orNull(IssuerHoldings.cathayFundCode(try inputBytes(input), symbol: try string(input, "symbol"))) },
    "IssuerHoldings.cathayAssetsDate": { input in orNull(IssuerHoldings.cathayAssetsDate(try inputBytes(input))) },
    "IssuerHoldings.capitalFundNo": { input in orNull(IssuerHoldings.capitalFundNo(try inputBytes(input), symbol: try string(input, "symbol"))) },
    "IssuerHoldings.fhtrustFundID": { input in orNull(IssuerHoldings.fhtrustFundID(try htmlInput(input), symbol: try string(input, "symbol"))) },
    "IssuerHoldings.ctbcFID": { input in orNull(IssuerHoldings.ctbcFID(try inputBytes(input), symbol: try string(input, "symbol"))) },
    "IssuerHoldings.ctbcToken": { input in orNull(IssuerHoldings.ctbcToken(try inputBytes(input))) },
    "IssuerDirectory.issuer": { input in orNull(IssuerDirectory.issuer(forFundName: try string(input, "name"))?.rawValue) },
    "IssuerDirectory.isBondFund": { input in IssuerDirectory.isBondFund(symbol: try string(input, "symbol"), fundType: try optionalString(input, "fundType")) },
    // Fugle
    "Fugle.decode": { input in quoteOutput(try Fugle.decode(inputBytes(input), expectedSymbol: string(input, "expectedSymbol")), fetchedAt: false) },
    "Fugle.decodeComponents": { input in snapshotOutput(try Fugle.decodeComponents(inputBytes(input), symbol: string(input, "symbol"))) },
    "Fugle.decodeHistory": { input in try Fugle.decodeHistory(inputBytes(input), symbol: string(input, "symbol")).map { ["date": $0.date, "close": $0.close] } },
]
