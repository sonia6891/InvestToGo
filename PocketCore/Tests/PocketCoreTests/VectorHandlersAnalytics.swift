import Foundation
@testable import PocketCore

private func flag(_ input: Any, _ key: String) throws -> Bool { (try VectorIO.object(input)[key] as? Bool) ?? false }

private func periodInput(_ input: Any) throws -> ReportPeriod {
    let p = try value(input, "period")
    switch try string(p, "kind") {
    case "month": return .month(try VectorIO.decode(YearMonth.self, try value(p, "month")))
    case "year": return .year(try int(p, "year"))
    case "yearToDate": return .yearToDate(try int(p, "year"))
    default: throw AppDataError("unknown period")
    }
}

private func historyInput(_ value: Any) throws -> SymbolHistory {
    let o = try VectorIO.object(value)
    return SymbolHistory(bars: try VectorIO.decode([DailyBar].self, o["bars"] ?? []),
                         dividends: try VectorIO.decode([DividendEvent].self, o["dividends"] ?? []),
                         splits: try VectorIO.decode([SplitEvent].self, o["splits"] ?? []),
                         suspect: (o["suspect"] as? Bool) ?? false, fromFugle: (o["fromFugle"] as? Bool) ?? false)
}

private func backtestInput(_ input: Any) throws -> BacktestInput {
    let legs = try (VectorIO.object(input)["legs"] as? [Any] ?? []).map { (symbol: try string($0, "symbol"), weight: try number($0, "weight")) }
    return BacktestInput(legs: legs, monthly: try number(input, "monthly"), start: try VectorIO.decode(YearMonth.self, try value(input, "start")),
                         end: try VectorIO.decode(YearMonth.self, try value(input, "end")), reinvest: try flag(input, "reinvest"))
}

private func cardOutput(_ c: ReportCard) -> [String: Any] {
    ["title": c.title, "dividends": c.dividends, "dcaMonths": c.dcaMonths, "reconciles": c.reconciles, "newDexCards": c.newDexCards,
     "level": c.level, "xpEarned": orNull(c.xpEarned), "notes": c.notes]
}

private func component(_ c: FundComponent) -> [String: Any] { ["symbol": c.symbol, "name": orNull(c.name), "weight": c.weight] }

private func changeOutput(_ c: SnapshotChange?) -> Any {
    guard let c else { return NSNull() }
    return ["from": c.from, "to": c.to, "added": c.added.map(component), "removed": c.removed.map(component),
            "changed": c.changed.map { component($0.component).merging(["delta": $0.delta]) { a, _ in a } },
            "changedCut": c.changedCut, "mixedSources": c.mixedSources, "isEmpty": c.isEmpty, "title": c.title]
}

private func rateInput(_ input: Any, _ key: String = "rate") throws -> FeeRate { try VectorIO.decode(FeeRate.self, try value(input, key)) }

/// A throwaway defaults suite holding `stored`, removed after `body`.
private func withStore<T>(_ input: Any, _ body: (UserDefaults) throws -> T) throws -> T {
    let name = "vectors-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else { throw AppDataError("no defaults suite") }
    defer { defaults.removePersistentDomain(forName: name) }
    SellCosts.save(try VectorIO.decode([String: FeeRate].self, try value(input, "stored")), in: defaults)
    return try body(defaults)
}

let analyticsHandlers: [String: VectorHandler] = [
    "Finance.xirr": { input in
        let flows = try (VectorIO.object(input)["flows"] as? [Any] ?? []).map { (date: try at($0, "date"), amount: try number($0, "amount")) }
        return orNull(Finance.xirr(flows))
    },
    "Backtest.maxDrawdown": { input in Backtest.maxDrawdown(try VectorIO.decode([Double].self, try value(input, "values"))) },
    "Backtest.run": { input in
        let raw = try VectorIO.object(try value(input, "history"))
        var history: [String: SymbolHistory] = [:]
        for (symbol, h) in raw { history[symbol] = try historyInput(h) }
        let r = Backtest.run(try backtestInput(input), history: history)
        return ["invested": r.invested, "endValue": r.endValue, "dividends": r.dividends, "xirr": orNull(r.xirr), "maxDrawdown": r.maxDrawdown,
                "curve": r.curve.map { ["month": $0.month.key, "invested": $0.invested, "value": $0.value] as [String: Any] }, "notes": r.notes]
    },
    "PocketReport.make": { input in
        let show = (try VectorIO.object(input)["showDividends"] as? Bool) ?? true
        return cardOutput(PocketReport.make(try periodInput(input), portfolio: try portfolioInput(input), now: try at(input, "now"), showDividends: show))
    },
    "ReportPeriod.title": { input in try periodInput(input).title(now: try at(input, "now")) },
    "PocketReport.earliestMonth": { input in orNull(PocketReport.earliestMonth(try portfolioInput(input), now: try at(input, "now"))?.key) },
    "PocketReport.noticeDue": { input in
        PocketReport.noticeDue(now: try at(input, "now"), seen: try string(input, "seen"), isMember: try flag(input, "isMember"), portfolio: try portfolioInput(input))
    },
    "SellCosts.fee": { input in SellCosts.fee(try number(input, "gross"), rate: try rateInput(input)) },
    "SellCosts.net": { input in
        SellCosts.net(try number(input, "gross"), stock: try flag(input, "stock"), bond: try flag(input, "bond"), rate: try rateInput(input), on: try at(input, "on"))
    },
    "SellCosts.taxRate": { input in SellCosts.taxRate(stock: try flag(input, "stock"), bond: try flag(input, "bond"), on: try at(input, "on")) },
    "SellCosts.preset": { input in try SellCosts.preset(for: try string(input, "broker")).map { try VectorIO.encode($0) } ?? NSNull() },
    "SellCosts.brokerKey": { input in SellCosts.brokerKey(try string(input, "broker")) },
    "SellCosts.rate": { input in
        try withStore(input) { d in
            let broker = try string(input, "broker")
            return ["rate": try VectorIO.encode(SellCosts.rate(for: broker, in: d)), "isSet": SellCosts.isSet(for: broker, in: d),
                    "note": SellCosts.rateNote(for: broker, in: d)] as [String: Any]
        }
    },
    "SellCosts.remember": { input in
        try withStore(input) { d in
            SellCosts.remember(try rateInput(input), for: try string(input, "broker"), in: d)
            return try VectorIO.encode(SellCosts.rates(in: d))
        }
    },
    "SnapshotDiff.compare": { input in
        changeOutput(SnapshotDiff.compare(old: try VectorIO.decode(ComponentSnapshot.self, try value(input, "old")),
                                          new: try VectorIO.decode(ComponentSnapshot.self, try value(input, "new"))))
    },
    "SnapshotDiff.latest": { input in changeOutput(SnapshotDiff.latest(try VectorIO.decode([ComponentSnapshot].self, try value(input, "history")))) },
    "SnapshotDiff.shortDay": { input in SnapshotDiff.shortDay(try string(input, "day"), year: try flag(input, "year")) },
]
