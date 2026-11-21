import XCTest
@testable import PocketCore

final class QuickDCATests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        GameRules.taipei.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private func holding(_ symbol: String) -> Holding {
        Holding(symbol: symbol, name: "測試", shares: 100, unitCost: 10, broker: "", strategy: .saving)
    }
    private func buy(_ symbol: String, _ on: Date) -> Trade { Trade(date: on, action: .buy, holding: holding(symbol)) }

    func testDefaultsOrder() {
        var p = Portfolio()
        let preset = QuickDCAPreset(symbol: "00878", amount: 3000, broker: "國泰")
        XCTAssertEqual(QuickDCA.defaults(preset: preset, onboardingSymbol: "0050", onboardingMonthly: 1, portfolio: p),
                       QuickDCADefaults(symbol: "00878", amount: 3000, broker: "國泰"))
        XCTAssertEqual(QuickDCA.defaults(preset: nil, onboardingSymbol: "006208", onboardingMonthly: 5000, portfolio: p),
                       QuickDCADefaults(symbol: "006208", amount: 5000, broker: ""))
        p.holdings = [holding("0050"), holding("00878")]
        p.trades = [buy("0050", date(2026, 10, 5)), buy("00878", date(2026, 11, 5))]
        XCTAssertEqual(QuickDCA.defaults(preset: nil, onboardingSymbol: nil, onboardingMonthly: nil, portfolio: p),
                       QuickDCADefaults(symbol: "00878", amount: nil, broker: ""))
        p.holdings = [holding("0050")]
        XCTAssertEqual(QuickDCA.defaults(preset: nil, onboardingSymbol: nil, onboardingMonthly: nil, portfolio: p).symbol, "0050")
        XCTAssertNil(QuickDCA.defaults(preset: nil, onboardingSymbol: nil, onboardingMonthly: 0, portfolio: p).amount)
    }

    func testEstimatedShares() {
        XCTAssertEqual(QuickDCA.estimatedShares(amount: 5000, close: 109), 45)
        XCTAssertEqual(QuickDCA.estimatedShares(amount: 5000, close: 100), 50)
        XCTAssertNil(QuickDCA.estimatedShares(amount: 50, close: 109))
        XCTAssertNil(QuickDCA.estimatedShares(amount: 5000, close: nil))
        XCTAssertNil(QuickDCA.estimatedShares(amount: 5000, close: 0))
        XCTAssertNil(QuickDCA.estimatedShares(amount: nil, close: 109))
    }

    func testCloseNote() {
        XCTAssertEqual(QuickDCA.closeNote(day: "2026-11-20"), "以 11/20 收盤價估算，可改成實際成交股數")
        XCTAssertEqual(QuickDCA.closeNote(day: "2026-01-05"), "以 1/5 收盤價估算，可改成實際成交股數")
        XCTAssertNil(QuickDCA.closeNote(day: ""))
    }

    func testProblemOrder() {
        XCTAssertEqual(QuickDCA.problem(known: false, shares: 45, amount: 5000), .unknownFund)
        XCTAssertEqual(QuickDCAProblem.unknownFund.message, "找不到這檔 ETF")
        XCTAssertEqual(QuickDCA.problem(known: true, shares: 45, amount: 0), .invalidAmount)
        XCTAssertEqual(QuickDCA.problem(known: true, shares: nil, amount: 5000), .invalidShares)
        XCTAssertEqual(QuickDCA.problem(known: true, shares: 0, amount: 5000), .invalidShares)
        XCTAssertNil(QuickDCA.problem(known: true, shares: 45, amount: 5000))
        XCTAssertNil(QuickDCAProblem.invalidShares.message)
    }

    func testAmountText() {
        XCTAssertEqual(QuickDCA.amountText(5000), "5,000"); XCTAssertEqual(QuickDCA.amountText(12000), "12,000"); XCTAssertEqual(QuickDCA.amountText(800), "800")
    }

    func testDCALoggedNeedsABuyStillInTheRecords() {
        let nov = YearMonth(year: 2026, month: 11)
        var game = GameState()
        game.dcaMonths = [nov]
        game.questsDone["2026-11"] = ["dcaLogged"]
        var p = Portfolio()
        p.game = game
        p.trades = [buy("0050", date(2026, 11, 6))]
        XCTAssertTrue(p.dcaLogged(in: nov))
        XCTAssertTrue(game.isDone(Quests.dcaLogged, in: nov, records: p))
        p.trades = []
        XCTAssertFalse(p.dcaLogged(in: nov))
        XCTAssertFalse(game.isDone(Quests.dcaLogged, in: nov, records: p))
        XCTAssertTrue(game.isDone(Quests.dcaLogged, in: nov))
        var noMonth = Portfolio()
        noMonth.game = GameState()
        noMonth.trades = [buy("0050", date(2026, 11, 6))]
        XCTAssertFalse(noMonth.dcaLogged(in: nov)); XCTAssertTrue(noMonth.hasBuy(in: nov))
        var other = GameState()
        other.questsDone["2026-11"] = ["dividendsViewed"]
        XCTAssertTrue(other.isDone(Quests.dividendsViewed, in: nov, records: Portfolio()))
    }

    private func backupData(preset: Any?) throws -> Data {
        let base = try JSONEncoder().encode(Portfolio())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        object["holdings"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([holding("0050")]))
        if let preset { object["quickDCA"] = preset } else { object.removeValue(forKey: "quickDCA") }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testOldBackupHasNoPreset() throws {
        let p = try Portfolio.decodeBackup(backupData(preset: nil))
        XCTAssertNil(p.quickDCA)
        XCTAssertEqual(p.holdings.count, 1)
    }

    func testInvalidPresetIsDroppedNotFatal() throws {
        let bad = try Portfolio.decodeBackup(backupData(preset: ["symbol": "bad code!", "amount": 5000, "broker": ""]))
        XCTAssertNil(bad.quickDCA)
        XCTAssertEqual(bad.holdings.count, 1)
        var p = Portfolio()
        p.quickDCA = QuickDCAPreset(symbol: "00878", amount: 3000, broker: "國泰")
        let back = try Portfolio.decodeBackup(JSONEncoder().encode(p))
        XCTAssertEqual(back.quickDCA, p.quickDCA)
    }
}
