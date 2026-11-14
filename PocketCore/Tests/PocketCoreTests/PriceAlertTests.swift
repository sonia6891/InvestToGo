import XCTest
@testable import PocketCore

/// `AlertEngine` and `Portfolio.alerts`: 到價提醒.
final class PriceAlertTests: XCTestCase {
    private func alert(_ symbol: String = "0050", above: Bool = true, _ price: Double, enabled: Bool = true) -> PriceAlert {
        PriceAlert(symbol: symbol, above: above, price: price, enabled: enabled)
    }

    // MARK: The brief's five

    func testAboveFiresAtOrOver() {
        let watch = alert(above: true, 100)
        XCTAssertEqual(AlertEngine.due([watch], prices: ["0050": 100], isMember: true), [watch.id], "At the target counts")
        XCTAssertEqual(AlertEngine.due([watch], prices: ["0050": 100.5], isMember: true), [watch.id])
        XCTAssertEqual(AlertEngine.due([watch], prices: ["0050": 99.9], isMember: true), [])
    }

    func testBelowFires() {
        let watch = alert(above: false, 50)
        XCTAssertEqual(AlertEngine.due([watch], prices: ["0050": 49], isMember: true), [watch.id])
        XCTAssertEqual(AlertEngine.due([watch], prices: ["0050": 50], isMember: true), [watch.id], "At the target counts")
        XCTAssertEqual(AlertEngine.due([watch], prices: ["0050": 50.01], isMember: true), [])
    }

    func testFiredAlertDoesNotRepeat() throws {
        var data = Portfolio()
        let watch = try data.addAlert(symbol: "0050", above: true, price: 100)
        let prices = ["0050": 120.0]
        let due = AlertEngine.due(data.alerts ?? [], prices: prices, isMember: true)
        XCTAssertEqual(due, [watch.id])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fired = data.fireAlerts(due, now: now)
        XCTAssertEqual(fired.map(\.id), due)
        XCTAssertEqual(data.alerts?.first?.enabled, false, "Fired once, then switched off")
        XCTAssertEqual(data.alerts?.first?.firedAt, now)
        XCTAssertEqual(AlertEngine.due(data.alerts ?? [], prices: prices, isMember: true), [], "The price is still over: no second notice")
        // Switched on again by hand, it can fire once more.
        data.alerts?[0].enabled = true
        XCTAssertEqual(AlertEngine.due(data.alerts ?? [], prices: prices, isMember: true), due)
    }

    func testNonMemberNeverFires() {
        let list = [alert(above: true, 100), alert("00878", above: false, 20)]
        let prices = ["0050": 150.0, "00878": 18.0]
        XCTAssertEqual(AlertEngine.due(list, prices: prices, isMember: false), [])
        XCTAssertEqual(AlertEngine.due(list, prices: prices, isMember: true), list.map(\.id))
    }

    func testMissingPriceSkipped() {
        let known = alert(above: true, 100), unknown = alert("00878", above: false, 20)
        XCTAssertEqual(AlertEngine.due([unknown, known], prices: ["0050": 100], isMember: true), [known.id])
        XCTAssertEqual(AlertEngine.due([unknown], prices: [:], isMember: true), [])
        // A price that is not a price is no price.
        XCTAssertEqual(AlertEngine.due([unknown], prices: ["00878": 0], isMember: true), [])
        XCTAssertEqual(AlertEngine.due([unknown], prices: ["00878": .nan], isMember: true), [])
    }

    // MARK: The list

    func testLimitTwentyAndNoTwins() throws {
        XCTAssertEqual(AlertEngine.limit, 20)
        var data = Portfolio()
        for i in 1...20 { try data.addAlert(symbol: "0050", above: true, price: Double(100 + i)) }
        XCTAssertEqual(data.alerts?.count, 20)
        XCTAssertThrowsError(try data.addAlert(symbol: "0056", above: true, price: 40)) { error in
            XCTAssertEqual(error.localizedDescription, "最多 20 個提醒，請先刪除不用的。")
        }
        XCTAssertEqual(data.alerts?.count, 20)
        var other = Portfolio()
        try other.addAlert(symbol: "0050", above: true, price: 200)
        XCTAssertThrowsError(try other.addAlert(symbol: "0050", above: true, price: 200)) { error in
            XCTAssertEqual(error.localizedDescription, "已經有一樣的提醒。")
        }
        XCTAssertNoThrow(try other.addAlert(symbol: "0050", above: false, price: 200), "The other direction is another alert")
        XCTAssertThrowsError(try other.addAlert(symbol: "0050", above: true, price: 0))
        XCTAssertThrowsError(try other.addAlert(symbol: "0050", above: true, price: -.infinity))
        XCTAssertThrowsError(try other.addAlert(symbol: "not a code", above: true, price: 10))
        XCTAssertEqual(other.alerts?.count, 2)
    }

    func testWatchingNeedsAnEnabledAlertAndAMember() {
        XCTAssertFalse(AlertEngine.watching([], isMember: true))
        XCTAssertFalse(AlertEngine.watching([alert(100, enabled: false)], isMember: true))
        XCTAssertFalse(AlertEngine.watching([alert(100)], isMember: false), "A lapsed member's alerts are not checked in the background")
        XCTAssertTrue(AlertEngine.watching([alert(100, enabled: false), alert(120)], isMember: true))
    }

    func testOnlyARecentPriceIsJudged() {
        let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
        XCTAssertTrue(AlertEngine.isCurrent(day: "2026-11-14", now: now))
        XCTAssertTrue(AlertEngine.isCurrent(day: "2026-11-13", now: now), "Friday's close on a Saturday")
        XCTAssertTrue(AlertEngine.isCurrent(day: "2026-11-07", now: now), "A week back, after a long holiday")
        XCTAssertFalse(AlertEngine.isCurrent(day: "2026-11-06", now: now))
        XCTAssertFalse(AlertEngine.isCurrent(day: "2026-08-01", now: now), "The price bundled with the app")
        XCTAssertFalse(AlertEngine.isCurrent(day: "", now: now))
        XCTAssertFalse(AlertEngine.isCurrent(day: "20261114", now: now))
    }

    func testMessageSaysTheCodeThePriceAndTheTarget() {
        let up = AlertEngine.message(alert(above: true, 200), price: 205.5)
        XCTAssertEqual(up, "0050 已到 \(decimal(205.5))，你設定的是高於 \(decimal(200))。")
        XCTAssertTrue(up.hasPrefix("0050 已到 "))
        let down = AlertEngine.message(alert("00878", above: false, 18.5), price: 18.2)
        XCTAssertEqual(down, "00878 已到 \(decimal(18.2))，你設定的是低於 \(decimal(18.5))。")
        for word in ["買", "賣", "建議", "進場", "出場", "機會"] {
            XCTAssertFalse(up.contains(word) || down.contains(word), "No advice: \(word)")
        }
        XCTAssertEqual(alert(above: true, 200).condition, "高於 \(decimal(200))")
        XCTAssertEqual(alert(above: false, 18.5).condition, "低於 \(decimal(18.5))")
    }

    // MARK: The records file

    func testFilesWithAndWithoutAlertsDecode() throws {
        // Written before 到價提醒: the key is simply missing.
        let old = Data(#"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}"#.utf8)
        XCTAssertNil(try Portfolio.decodeBackup(old).alerts)
        var data = Portfolio()
        try data.addAlert(symbol: "0050", above: true, price: 200)
        let second = try data.addAlert(symbol: "00679B", above: false, price: 27.5)
        data.fireAlerts([second.id], now: Date(timeIntervalSince1970: 1_800_000_000))
        let back = try Portfolio.decodeBackup(JSONEncoder().encode(data))
        XCTAssertEqual(back.alerts, data.alerts)
        XCTAssertEqual(back.alerts?.map(\.enabled), [true, false])
        // Written by hand with only what an alert needs: it has never fired.
        let bare = Data(#"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{},"alerts":[{"id":"11111111-2222-3333-4444-555555555555","symbol":"0050","above":true,"price":200,"enabled":true}]}"#.utf8)
        let read = try Portfolio.decodeBackup(bare)
        XCTAssertEqual(read.alerts?.first?.symbol, "0050")
        XCTAssertNil(read.alerts?.first?.firedAt)
    }

    func testBackupRejectsBadAlerts() throws {
        func encoded(_ alerts: [PriceAlert]) throws -> Data {
            var data = Portfolio()
            data.alerts = alerts
            return try JSONEncoder().encode(data)
        }
        XCTAssertNoThrow(try Portfolio.decodeBackup(encoded([alert(200), alert("00878", above: false, 20)])))
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded([alert("abc", 200)])), "Not a code")
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded([alert(0)])), "No price")
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded([alert(2_000_000)])), "Not a price")
        let twin = alert(200)
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded([twin, twin])), "The same id twice")
        XCTAssertThrowsError(try Portfolio.decodeBackup(encoded((1...21).map { alert(Double($0)) })), "More than the app keeps")
    }

    func testMergeKeepsWhatIsHereAndStopsAtTheLimit() throws {
        var data = Portfolio()
        let mine = try data.addAlert(symbol: "0050", above: true, price: 200)
        var theirs = mine
        theirs.enabled = false
        let extra = (1...25).map { alert("0056", above: false, Double($0)) }
        data.mergeAlerts([theirs] + extra)
        XCTAssertEqual(data.alerts?.count, 20)
        XCTAssertEqual(data.alerts?.first, theirs, "The backup's copy of a known alert replaces it")
        XCTAssertEqual(data.alerts?.dropFirst().map(\.id), extra.prefix(19).map(\.id))
        XCTAssertNoThrow(try Portfolio.decodeBackup(JSONEncoder().encode(data)))
        var empty = Portfolio()
        empty.mergeAlerts([])
        XCTAssertNil(empty.alerts, "Nothing to merge leaves an older file as it was")
    }
}
