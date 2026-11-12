import XCTest
@testable import ETFToGo

/// The dex card's words and the price-move text, without the simulator UI.
final class DexCardTests: XCTestCase {
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!

    func testSkillLineIsPlainFactsWithoutAdvice() {
        let fee = AnnualFeeCatalog.bundled?.records["0050"]
        let funds = [
            Fund(id: "0050", name: "元大台灣50", strategy: .saving),
            Fund(id: "0056", name: "元大高股息", strategy: .income),
            Fund(id: "00679B", name: "元大美債20年", strategy: .unclassified, fundType: "國外成分證券指數股票型基金(債券)"),
            Fund(id: "00631L", name: "元大台灣50正2", strategy: .risk),
            Fund(id: "00400A", name: "主動國泰動能高息", strategy: .income),
            Fund(id: "00881", name: "國泰台灣5G+", strategy: .unclassified),
        ]
        for fund in funds {
            for withFee in [true, false] {
                let line = DexText.skill(fund, fee: withFee ? fee : nil)
                for word in ["推薦", "建議", "最好", "必買", "適合", "值得", "首選"] {
                    XCTAssertFalse(line.contains(word), "\(fund.id): 「\(line)」 has \(word)")
                }
                XCTAssertTrue(line.hasSuffix("。"))
                XCTAssertFalse(line.contains("\n"), "One line")
            }
        }
        XCTAssertEqual(DexText.skill(funds[0], fee: nil), "依市值挑選大型公司，一次買進一籃股票；年度費用尚未公布。")
        XCTAssertTrue(DexText.skill(funds[2], fee: nil).hasPrefix("以債券為主"))
        XCTAssertTrue(DexText.skill(funds[3], fee: nil).hasPrefix("每天追蹤指數漲跌的倍數"))
        XCTAssertTrue(DexText.skill(funds[4], fee: nil).hasPrefix("由經理人主動挑選持股；挑選配息較高的股票"))
        if let fee {
            XCTAssertTrue(DexText.skill(funds[0], fee: fee).hasSuffix("；\(String(fee.year)) 年總費用率 \(decimal(fee.total))%。"))
        }
    }

    func testBarsNameFeeAndHistoryAsFactsAndShowDashWhenMissing() {
        let fund = Fund(id: "0050", name: "元大台灣50", strategy: .saving, listingDate: "2003-06-30")
        var facts = DexFacts()
        facts.feeRate = ["0050": 0.22, "0056": 0.6]
        facts.listed = ["0050": DataChecks.date("2003-06-30")!, "0056": DataChecks.date("2007-12-26")!]
        let other = Fund(id: "0056", name: "元大高股息", strategy: .income)
        let stats = Dex.stats(for: fund, among: [fund, other], facts: facts)
        let bars = DexText.bars(stats, fund: fund, facts: facts, now: now)
        XCTAssertEqual(bars.map(\.id), ["fee", "size", "yield", "volatility", "history"])
        XCTAssertEqual(bars.map(\.title), ["低費用", "規模", "殖利率", "波動", "上市時間"])
        XCTAssertEqual(bars[0], DexBar(id: "fee", title: "低費用", blocks: 10, value: "0.22%"), "The lower fee has more blocks")
        XCTAssertEqual(bars[4], DexBar(id: "history", title: "上市時間", blocks: 10, value: "23 年"), "The older fund has more blocks")
        for missing in bars[1...3] { XCTAssertEqual(missing.blocks, 0); XCTAssertEqual(missing.value, "—") }
        let young = DexText.bars(Dex.stats(for: other, among: [fund, other], facts: facts), fund: other, facts: facts, now: now)
        XCTAssertEqual(young[0].blocks, 5); XCTAssertEqual(young[4].blocks, 5)
    }

    func testRiskStarsFollowTheAssetType() {
        XCTAssertEqual(DexText.riskStars(Fund(id: "00631L", name: "元大台灣50正2", strategy: .risk)), 5)
        XCTAssertEqual(DexText.riskStars(Fund(id: "00679B", name: "元大美債20年", strategy: .unclassified)), 3)
        XCTAssertEqual(DexText.riskStars(Fund(id: "0050", name: "元大台灣50", strategy: .saving, fundType: "國內成分證券指數股票型基金")), 4)
    }

    func testChangeTextAlwaysHasAnArrowAndAPercentage() {
        XCTAssertEqual(SkinChange.text(percent: 0.751, amount: nil), "▲ 0.75%")
        XCTAssertEqual(SkinChange.text(percent: -0.27, amount: nil), "▼ 0.27%")
        XCTAssertEqual(SkinChange.text(percent: 0.004, amount: nil), "－ 0.00%", "Rounds to unchanged: no direction")
        XCTAssertEqual(SkinChange.text(percent: 0, amount: nil), "－ 0.00%")
        XCTAssertEqual(SkinChange.text(percent: 0.75, amount: 1.25), "▲ 1.25 (+0.75%)")
        XCTAssertEqual(SkinChange.text(percent: -1.5, amount: -0.9), "▼ 0.90 (-1.50%)")
    }

    func testSteppedLineKeepsFirstAndLastDay() {
        let points = (0..<250).map { ValuePoint(date: Date(timeIntervalSince1970: Double($0) * 86400), value: Double($0)) }
        let thinned = SkinTrendLine.thinned(points, to: 32)
        XCTAssertEqual(thinned.count, 32)
        XCTAssertEqual(thinned.first?.value, 0)
        XCTAssertEqual(thinned.last?.value, 249)
        XCTAssertEqual(SkinTrendLine.thinned(Array(points.prefix(10)), to: 32).count, 10, "Short series are left alone")
    }
}
