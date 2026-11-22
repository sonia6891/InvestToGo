import Foundation
@testable import PocketCore

/// A portfolio as vector output: encoded the way the app saves it, with every set sorted so both platforms agree.
func normalizedPortfolio(_ value: Portfolio) throws -> Any {
    guard var root = try VectorIO.encode(value) as? [String: Any] else { throw AppDataError("portfolio is not an object") }
    if let list = root["favorites"] as? [String] { root["favorites"] = list.sorted() }
    if var game = root["game"] as? [String: Any] {
        for key in ["celebratedAchievements", "rewardKeys"] { if let list = game[key] as? [String] { game[key] = list.sorted() } }
        if let months = game["dcaMonths"] as? [[String: Any]] {
            game["dcaMonths"] = months.sorted { (($0["year"] as? Int ?? 0) * 100 + ($0["month"] as? Int ?? 0)) < (($1["year"] as? Int ?? 0) * 100 + ($1["month"] as? Int ?? 0)) }
        }
        if let done = game["questsDone"] as? [String: [String]] { game["questsDone"] = done.mapValues { $0.sorted() } }
        root["game"] = game
    }
    return root
}

/// The bytes a case reads: a fixture file, or the text itself.
func inputBytes(_ input: Any) throws -> Data {
    let object = try VectorIO.object(input)
    if object["file"] != nil { return try VectorIO.file(input) }
    return Data(try string(input, "text").utf8)
}

func int(_ input: Any, _ key: String) throws -> Int {
    guard let value = try VectorIO.object(input)[key] as? NSNumber else { throw AppDataError("vector input has no \(key)") }
    return value.intValue
}

func value(_ input: Any, _ key: String) throws -> Any {
    guard let value = try VectorIO.object(input)[key] else { throw AppDataError("vector input has no \(key)") }
    return value
}

func scenario(_ input: Any) throws -> ComboScenario {
    guard let value = ComboScenario(rawValue: try string(input, "scenario")) else { throw AppDataError("unknown scenario") }
    return value
}

func part(_ p: ComboMath.Part) -> [String: Any] { ["start": p.start, "invested": p.invested, "value": p.value, "cash": p.cash, "end": p.end] }

let modelHandlers: [String: VectorHandler] = [
    "Portfolio.decodeBackup": { input in
        let object = try VectorIO.object(input)
        let limit = (object["limit"] as? NSNumber)?.intValue ?? 5_000_000
        return try normalizedPortfolio(Portfolio.decodeBackup(inputBytes(input), limit: limit))
    },
    "BackupImport.decode": { input in try normalizedPortfolio(BackupImport.decode(inputBytes(input))) },
    "GoalPlanner.monthlyContribution": { input in
        GoalPlanner.monthlyContribution(target: try number(input, "target"), years: try int(input, "years"), current: try number(input, "current"), annualReturn: try number(input, "annualReturn"))
    },
    "GoalPlanner.scenarios": { input in
        GoalPlanner.scenarios(target: try number(input, "target"), years: try int(input, "years"), current: try number(input, "current"), annualReturn: try number(input, "annualReturn"))
            .map { ["scenario": $0.scenario.rawValue, "annualReturn": $0.annualReturn, "monthly": $0.monthly] as [String: Any] }
    },
    "ComboMath.project": { input in
        let settings = try VectorIO.decode(ComboSettings.self, try value(input, "settings"))
        let result = ComboMath.project(stockStart: try number(input, "stockStart"), etfStart: try number(input, "etfStart"), settings: settings,
                                       stockShare: try number(input, "stockShare"), years: try int(input, "years"), scenario: try scenario(input))
        return ["stock": part(result.stock), "etf": part(result.etf), "invested": result.invested, "end": result.end] as [String: Any]
    },
    "PlanMath.project": { input in
        try PlanMath.project(VectorIO.decode(LegacyPlan.self, try value(input, "plan"))).map {
            ["year": $0.year, "invested": $0.invested, "cash": $0.cash, "contributed": $0.contributed, "dividends": $0.dividends, "total": $0.total] as [String: Any]
        }
    },
    "AlertEngine.due": { input in
        let alerts = try VectorIO.decode([PriceAlert].self, try value(input, "alerts"))
        let prices = try VectorIO.decode([String: Double].self, try value(input, "prices"))
        let member = (try VectorIO.object(input)["isMember"] as? Bool) ?? false
        return AlertEngine.due(alerts, prices: prices, isMember: member).map(\.uuidString)
    },
    "AlertEngine.isCurrent": { input in AlertEngine.isCurrent(day: try string(input, "day"), now: try at(input, "now")) },
    "ResearchMath.exposures": { input in
        let portfolio = try VectorIO.decode(Portfolio.self, try value(input, "portfolio"))
        let stocks = Set(try VectorIO.decode([String].self, try value(input, "stocks")))
        return ResearchMath.exposures(portfolio, stocks: stocks).map {
            ["symbol": $0.symbol, "name": $0.name, "value": $0.value, "funds": $0.funds.sorted()] as [String: Any]
        }
    },
    "ResearchMath.overlap": { input in
        ResearchMath.overlap(try VectorIO.decode(ComponentSnapshot.self, try value(input, "left")), try VectorIO.decode(ComponentSnapshot.self, try value(input, "right"))).map {
            ["symbol": $0.symbol, "name": $0.name, "left": $0.left, "right": $0.right] as [String: Any]
        }
    },
    "ComponentSnapshot.imported": { input in
        try VectorIO.encode(ComponentSnapshot.imported(Data(try string(input, "text").utf8), symbol: try string(input, "symbol")))
    },
    "PriceHistory.validate": { input in try VectorIO.decode(PriceHistory.self, try value(input, "history")).validate(); return true },
    "PerformanceStats.init": { input in
        let stats = try PerformanceStats(VectorIO.decode(PriceHistory.self, try value(input, "history")))
        return ["change": stats.change, "annualized": orNull(stats.annualized), "drawdown": stats.drawdown, "volatility": orNull(stats.volatility)] as [String: Any]
    },
    "FeeRecord.validate": { input in try VectorIO.decode(FeeRecord.self, try value(input, "fee")).validate(); return true },
    "YearMonth.init": { input in
        let month = YearMonth(try at(input))
        return ["year": month.year, "month": month.month, "key": month.key] as [String: Any]
    },
    "YearMonth.fromKey": { input in
        guard let month = YearMonth(key: try string(input, "key")) else { return NSNull() }
        return ["year": month.year, "month": month.month] as [String: Any]
    },
]
