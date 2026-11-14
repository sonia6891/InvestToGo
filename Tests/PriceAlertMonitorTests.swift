import XCTest
@testable import ETFToGo

/// What a check asked for and what it posted. Only ever touched on the main actor, by the tests below.
private final class AlertLog {
    var asked: [[String]] = []
    var posted: [(alert: PriceAlert, price: Double)] = []
    var memberAnswers: [Bool] = []
    /// The answers in turn; the last one from then on.
    func member() -> Bool { memberAnswers.count > 1 ? memberAnswers.removeFirst() : (memberAnswers.first ?? true) }
}

/// 到價提醒 in the app: the check (`PriceAlertMonitor`), the store's list, the route, the Info.plist keys and the
/// records of a phone that was locked at launch.
final class PriceAlertMonitorTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: directory.appendingPathComponent("p.json").path)
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent("p.json") }

    /// A trade of `day` (today when nil) that arrived just now, so it is the newest price the store knows.
    private func quote(_ symbol: String, _ price: Double, day: String? = nil, trial: Bool? = nil) -> Quote {
        Quote(symbol: symbol, price: price, changePercent: nil, date: day ?? DataChecks.day(), fetchedAt: Date(), trial: trial)
    }

    // MARK: The check

    @MainActor func testCheckNotifiesOnceAndSwitchesTheAlertOff() async throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 100)
        try store.addAlert(symbol: "00878", above: false, price: 20)
        let log = AlertLog()
        let now = Date()
        let prices: (PortfolioStore, [String]) async -> Void = { store, symbols in
            log.asked.append(symbols)
            store.liveQuotes["0050"] = self.quote("0050", 120)
            store.liveQuotes["00878"] = self.quote("00878", 21)
        }
        await PriceAlertMonitor.check(store, now: now, isMember: { true }, refresh: prices, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.asked, [["0050", "00878"]], "Only the codes being watched are asked for")
        XCTAssertEqual(log.posted.map(\.alert.symbol), ["0050"])
        XCTAssertEqual(log.posted.first?.price, 120)
        XCTAssertEqual(store.alerts.map(\.enabled), [false, true], "Fired once, then switched off; 00878 is still above 20")
        XCTAssertEqual(store.alerts.first?.firedAt, now)
        XCTAssertNil(store.alerts.last?.firedAt)
        XCTAssertEqual(PortfolioStore(url: file).alerts.map(\.enabled), [false, true], "Saved with the records")
        // The price is still over 100: the next check says nothing more, and no longer asks for 0050.
        await PriceAlertMonitor.check(store, now: now, isMember: { true }, refresh: prices, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.posted.count, 1)
        XCTAssertEqual(log.asked.last, ["00878"])
        // Switched on again by hand, it fires once more.
        try store.setAlert(try XCTUnwrap(store.alerts.first).id, enabled: true)
        await PriceAlertMonitor.check(store, now: now, isMember: { true }, refresh: prices, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.posted.map(\.alert.symbol), ["0050", "0050"])
        XCTAssertEqual(store.alerts.map(\.enabled), [false, true])
        // With nothing switched on, nobody is asked for anything.
        try store.setAlert(try XCTUnwrap(store.alerts.last).id, enabled: false)
        let before = log.asked.count
        await PriceAlertMonitor.check(store, now: now, isMember: { true }, refresh: prices, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.asked.count, before)
    }

    /// A lapsed member's alerts stay in the list; no price is asked for and nothing is posted.
    @MainActor func testLapsedMemberIsNeverNotified() async throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 100)
        store.liveQuotes["0050"] = quote("0050", 120)
        let log = AlertLog()
        await PriceAlertMonitor.check(store, isMember: { false }, refresh: { _, symbols in log.asked.append(symbols) }, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertTrue(log.asked.isEmpty)
        XCTAssertTrue(log.posted.isEmpty)
        XCTAssertEqual(store.alerts.map(\.enabled), [true], "The alert is kept as it was")
        // The membership ended while the prices were on their way: still nothing.
        log.memberAnswers = [true, false]
        await PriceAlertMonitor.check(store, isMember: { log.member() }, refresh: { _, symbols in log.asked.append(symbols) }, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.asked.count, 1)
        XCTAssertTrue(log.posted.isEmpty)
        XCTAssertEqual(store.alerts.map(\.enabled), [true])
    }

    /// A second check that runs while the first is waiting for prices fires the alert; the first then finds it done.
    @MainActor func testOverlappingChecksFireOnce() async throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 100)
        let log = AlertLog()
        await PriceAlertMonitor.check(store, isMember: { true }, refresh: { store, _ in
            store.liveQuotes["0050"] = self.quote("0050", 120)
            await PriceAlertMonitor.check(store, isMember: { true }, refresh: { _, _ in }, notify: { log.posted.append((alert: $0, price: $1)) })
        }, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.posted.count, 1)
    }

    /// Only a real trade of the last few days is judged: never a trial match, never a price from weeks ago.
    @MainActor func testOldOrTrialPriceFiresNothing() async throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 100)
        let log = AlertLog()
        let old = DataChecks.day(Date().addingTimeInterval(-30 * 86_400))
        store.liveQuotes["0050"] = quote("0050", 120, day: old)
        XCTAssertNil(store.alertPrice("0050"))
        await PriceAlertMonitor.check(store, isMember: { true }, refresh: { _, _ in }, notify: { log.posted.append((alert: $0, price: $1)) })
        store.liveQuotes["0050"] = quote("0050", 120, trial: true)
        XCTAssertNil(store.alertPrice("0050"))
        await PriceAlertMonitor.check(store, isMember: { true }, refresh: { _, _ in }, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertTrue(log.posted.isEmpty)
        XCTAssertEqual(store.alerts.map(\.enabled), [true])
        store.liveQuotes["0050"] = quote("0050", 120)
        XCTAssertEqual(store.alertPrice("0050"), 120)
        await PriceAlertMonitor.check(store, isMember: { true }, refresh: { _, _ in }, notify: { log.posted.append((alert: $0, price: $1)) })
        XCTAssertEqual(log.posted.count, 1)
    }

    // MARK: The list

    @MainActor func testStoreKeepsTwentyAndRemoves() throws {
        let store = PortfolioStore(url: file)
        XCTAssertTrue(store.alerts.isEmpty)
        for i in 1...20 { try store.addAlert(symbol: "0050", above: i % 2 == 0, price: Double(i)) }
        XCTAssertThrowsError(try store.addAlert(symbol: "0056", above: true, price: 40)) { error in
            XCTAssertEqual(error.localizedDescription, "最多 20 個提醒，請先刪除不用的。")
        }
        let first = try XCTUnwrap(store.alerts.first)
        try store.removeAlert(first.id)
        XCTAssertEqual(store.alerts.count, 19)
        XCTAssertFalse(store.alerts.contains { $0.id == first.id })
        XCTAssertNoThrow(try store.addAlert(symbol: "0056", above: true, price: 40))
        XCTAssertEqual(PortfolioStore(url: file).alerts.count, 20)
    }

    @MainActor func testBackupCarriesTheAlerts() throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 200)
        let backup = try Data(contentsOf: store.export())
        let other = PortfolioStore(url: directory.appendingPathComponent("other.json"))
        try other.addAlert(symbol: "00878", above: false, price: 20)
        try other.importBackup(backup)
        XCTAssertEqual(other.alerts.map(\.symbol), ["00878", "0050"], "What was here stays; the backup's alert is added")
        try other.importBackup(backup)
        XCTAssertEqual(other.alerts.count, 2, "The same backup again adds nothing")
    }

    @MainActor func testStatusWords() {
        var alert = PriceAlert(symbol: "0050", above: true, price: 200)
        XCTAssertEqual(PriceAlertsView.status(alert), "監看中")
        alert.enabled = false
        XCTAssertEqual(PriceAlertsView.status(alert), "已停用")
        let fired = Date()
        alert.firedAt = fired
        XCTAssertEqual(PriceAlertsView.status(alert), "\(monthDay(fired)) 已到價，提醒已停用")
        alert.enabled = true
        XCTAssertEqual(PriceAlertsView.status(alert), "監看中・上次到價 \(monthDay(fired))")
    }

    /// A fired alert leaves a line in 通知中心 that opens 到價提醒.
    @MainActor func testFiredAlertIsInTheNoticeCentre() async throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 100)
        XCTAssertFalse(AppNotice.all(store).contains { $0.kind == "到價提醒" })
        store.liveQuotes["0050"] = quote("0050", 120)
        await PriceAlertMonitor.check(store, isMember: { true }, refresh: { _, _ in }, notify: { _, _ in })
        let notice = try XCTUnwrap(AppNotice.all(store).first { $0.kind == "到價提醒" })
        XCTAssertEqual(notice.text, "0050 已到你設定的價格（高於 100）")
        XCTAssertEqual(notice.route, .priceAlerts)
        XCTAssertFalse(notice.id.contains(","), "Read notices are kept as a comma-separated list")
    }

    // MARK: Route and Info.plist

    func testOpenRouteNeedsUITesting() {
        XCTAssertEqual(AppRoute.launchStack(["--ui-testing", "--open", "priceAlerts"]), [.feature(.tools), .priceAlerts])
        XCTAssertNil(AppRoute.launchStack(["--open", "priceAlerts"]))
    }

    /// iOS stops the app at launch when the task registered in code is not listed in Info.plist (project.yml).
    func testInfoPlistAllowsTheBackgroundTask() {
        XCTAssertEqual(PriceAlertMonitor.identifier, "tw.sonia.etftogo.alerts")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String], [PriceAlertMonitor.identifier])
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String], ["fetch"])
    }

    // MARK: A phone that was locked at launch

    /// The background check can start the app while the phone is locked: the records file is there but cannot be
    /// opened. That is not a damaged file: nothing is said, nothing is saved over it, and it is read once it opens.
    @MainActor func testRecordsLockedAtLaunchAreReadLater() throws {
        let first = PortfolioStore(url: file)
        try first.save(Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving))
        try first.addAlert(symbol: "0050", above: true, price: 200)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        if (try? Data(contentsOf: file)) != nil { throw XCTSkip("This machine reads the file whatever its permissions") }

        let store = PortfolioStore(url: file)
        var redone = 0
        store.onRecordsRead = { _ in redone += 1 }
        XCTAssertTrue(store.recordsLocked)
        XCTAssertNil(store.message, "Not the 「無法讀取既有資料」 of a damaged file")
        XCTAssertTrue(store.data.holdings.isEmpty)
        XCTAssertThrowsError(try store.addAlert(symbol: "0056", above: true, price: 40), "Nothing is written over records that were not read")
        XCTAssertFalse(store.reloadIfLocked(), "Still locked")
        XCTAssertEqual(redone, 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertTrue(store.reloadIfLocked())
        XCTAssertFalse(store.recordsLocked)
        XCTAssertEqual(store.data.holdings.map(\.symbol), ["0050"])
        XCTAssertEqual(store.alerts.map(\.symbol), ["0050"])
        XCTAssertEqual(redone, 1, "The launch steps that read the records are done again, once")
        XCTAssertNoThrow(try store.addAlert(symbol: "0056", above: true, price: 40))
        XCTAssertTrue(store.reloadIfLocked())
        XCTAssertEqual(redone, 1)
        XCTAssertEqual(store.alerts.count, 2, "A second call reads nothing again")
    }

    /// A file that is really damaged is still reported as before.
    @MainActor func testDamagedRecordsStillSaySo() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let store = PortfolioStore(url: file)
        XCTAssertFalse(store.recordsLocked)
        XCTAssertEqual(store.message, "無法讀取既有資料，原始檔已保留。請先匯出或檢查備份。")
        XCTAssertTrue(store.reloadIfLocked(), "Nothing to wait for")
    }
}
