import Foundation

// Wires the dex (PocketCore `Dex`, spec 6.4 and G5) to facts the app already keeps: the published annual fees, the
// official dividend announcements with the latest close, stored price histories and the listing dates. The app has
// no fund-size source yet, so `aum` stays empty and the 規模 bar shows "—" until one is added.

extension PortfolioStore {
    /// The catalogue without duplicate codes: `Dex.stats` ranks unique funds.
    var dexFunds: [Fund] {
        var seen = Set<String>()
        return funds.filter { seen.insert($0.id).inserted }
    }

    /// The catalogue entry, or a bare fund when the code is not in it.
    func dexFund(_ symbol: String) -> Fund {
        funds.first { $0.id == symbol } ?? Fund(id: symbol, name: name(for: symbol), strategy: .unclassified)
    }

    /// Every fact the five bars rank on, for the whole catalogue (bands are relative, so all funds take part). The
    /// yield is `trailingYield` (ToolsView), the same figure the comparison page shows.
    func dexFacts() -> DexFacts {
        var facts = DexFacts()
        if let fees = AnnualFeeCatalog.bundled?.records { facts.feeRate = fees.mapValues(\.total) }
        for fund in dexFunds {
            if let yield = trailingYield(fund.id) { facts.yield[fund.id] = yield }
            if let date = fund.listingDate.flatMap(DataChecks.date) { facts.listed[fund.id] = date }
        }
        for (symbol, history) in data.histories ?? [:] {
            if let volatility = (try? PerformanceStats(history))?.volatility { facts.volatility[symbol] = volatility * 100 }
        }
        return facts
    }

    /// The collected cards in code order, plus the card that was opened and the one on screen, even when collecting
    /// them was not saved: what the dex card swipes through.
    func dexDeck(opened: String, showing: String) -> [String] {
        var codes = Set((data.game ?? GameState()).collected.keys)
        codes.insert(opened); codes.insert(showing)
        return codes.sorted()
    }

    /// Collects the card on the first visit to its ETF page (spec 6.4) and finishes the visit's quests
    /// (`GameState.visitFund`). A failed save leaves the card uncollected and is not reported: the page still works.
    func collectDexCard(_ symbol: String, now: Date = Date()) -> FundVisit {
        var visit = FundVisit()
        do { try updateGame { visit = $0.visitFund(symbol, now: now) } } catch { return FundVisit() }
        return visit
    }

    /// Puts the fund in the three-fund comparison, dropping the oldest when it is full; nothing when it is already
    /// there. 「PK 比一比」 calls it directly, 「加入比較」 through `addToComparison`, which also reports the result.
    func appendToComparison(_ symbol: String) throws {
        var list = data.comparison ?? []
        guard !list.contains(symbol) else { return }
        if list.count >= 3 { list.removeFirst() }
        list.append(symbol)
        var next = data
        next.comparison = list
        try commit(next)
    }
}

/// One of the card's five bars: 1–10 blocks, 0 when the fact is missing.
struct DexBar: Identifiable, Equatable {
    /// "fee", "size", "yield", "volatility", "history"; the UI identifier is "dex-bar-<id>".
    let id: String
    let title: String
    let blocks: Int
    /// The fact itself, or "—".
    let value: String
}

/// The card's words. Facts only: no total score, no recommendation (spec G5 and the copy rule).
enum DexText {
    /// The fee and history bars are named for what more blocks means (lower fee, longer listed), so a long bar reads
    /// as a fact and not as advice.
    static func bars(_ stats: DexStats, fund: Fund, facts: DexFacts, now: Date = Date()) -> [DexBar] {
        func shown(_ blocks: Int, _ text: String?) -> String { blocks > 0 ? (text ?? "—") : "—" }
        let listed = facts.listed[fund.id].map { date -> String in
            let years = GameRules.taipei.dateComponents([.year], from: date, to: now).year ?? 0
            return years >= 1 ? "\(years) 年" : "未滿 1 年"
        }
        return [
            DexBar(id: "fee", title: "低費用", blocks: stats.fee, value: shown(stats.fee, facts.feeRate[fund.id].map { "\(decimal($0))%" })),
            DexBar(id: "size", title: "規模", blocks: stats.size, value: shown(stats.size, facts.aum[fund.id].map { decimal($0) })),
            DexBar(id: "yield", title: "殖利率", blocks: stats.yield, value: shown(stats.yield, facts.yield[fund.id].map { "\(decimal($0))%" })),
            DexBar(id: "volatility", title: "波動", blocks: stats.volatility, value: shown(stats.volatility, facts.volatility[fund.id].map { "\(decimal($0))%" })),
            DexBar(id: "history", title: "上市時間", blocks: stats.history, value: shown(stats.history, listed)),
        ]
    }

    /// 特技: one plain line from the fund's type and its published fee. It says what the fund holds, never who should
    /// buy it.
    static func skill(_ fund: Fund, fee: AnnualExpense?) -> String {
        var kind: String
        switch (fund.structure, DexSeries.of(fund)) {
        case ("槓桿型", _): kind = "每天追蹤指數漲跌的倍數，漲跌都會放大"
        case ("反向型", _): kind = "每天追蹤指數的反向漲跌，和指數走反方向"
        case (_, .bond): kind = "以債券為主，價格主要跟著利率變動"
        case (_, .highDividend): kind = "挑選配息較高的股票，一次買進一籃"
        case (_, .marketCap): kind = "依市值挑選大型公司，一次買進一籃股票"
        case (_, .theme): kind = fund.assetKind == "商品" ? "追蹤商品或期貨價格，不是一籃股票" : "集中買進同一主題的一籃股票"
        }
        if fund.isActive { kind = "由經理人主動挑選持股；" + kind }
        let cost = fee.map { "\(String($0.year)) 年總費用率 \(decimal($0.total))%" } ?? "年度費用尚未公布"
        return "\(kind)；\(cost)。"
    }

    /// 星等 as a labelled fact: the rough risk level by asset type (`Fund.riskLevel`), out of five.
    static func riskStars(_ fund: Fund) -> Int {
        switch fund.riskLevel {
        case "高": return 5
        case "中高": return 4
        case "中": return 3
        default: return 0
        }
    }
}
