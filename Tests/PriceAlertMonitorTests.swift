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

    // MARK: When the checks run

    /// Coming back to the app again and again asks for the watched prices once in five minutes, not every time.
    func testChecksOnReturnAreFiveMinutesApart() {
        XCTAssertEqual(PriceAlertMonitor.foregroundGap, 300)
        var gate = CheckGate(gap: PriceAlertMonitor.foregroundGap)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func comeBack(after seconds: TimeInterval) -> Bool { gate.open(at: start.addingTimeInterval(seconds)) }
        XCTAssertTrue(comeBack(after: 0), "The first return checks")
        XCTAssertFalse(comeBack(after: 10))
        XCTAssertFalse(comeBack(after: 299), "Within five minutes of the last check nothing is done")
        XCTAssertTrue(comeBack(after: 300))
        // The gap is counted from the last check that ran, not from a return that was skipped.
        XCTAssertFalse(comeBack(after: 599))
        XCTAssertTrue(comeBack(after: 600))
        XCTAssertEqual(gate.last, start.addingTimeInterval(600))
        // A clock that was set back does not stop the checks.
        XCTAssertTrue(comeBack(after: -3600))
        XCTAssertFalse(comeBack(after: -3500))
    }

    /// The background task is reported as finished by its run or by its expiration, whichever is first, never both.
    func testOnceFlagIsClaimedOnce() {
        let flag = OnceFlag(), lock = NSLock()
        var claims = 0
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            if flag.claim() { lock.lock(); claims += 1; lock.unlock() }
        }
        XCTAssertEqual(claims, 1)
        XCTAssertFalse(flag.claim())
    }

    /// 到價提醒's quiet refresh leaves 更新報價 alone: the button does not say 「更新中…」 and a tap on it is answered.
    @MainActor func testQuietRefreshLeavesTheUsersOwnRefreshAlone() {
        let store = PortfolioStore(url: file)
        XCTAssertTrue(store.beginRefresh(quiet: true))
        XCTAssertFalse(store.refreshing, "The buttons do not show a refresh nobody asked for")
        XCTAssertTrue(store.fetchingQuotes, "Live polling still waits for it")
        XCTAssertFalse(store.beginRefresh(quiet: true), "A second quiet refresh is left to the next check")
        XCTAssertTrue(store.beginRefresh(quiet: false), "The tap on 更新報價 is answered while the quiet one runs")
        XCTAssertTrue(store.refreshing)
        XCTAssertFalse(store.beginRefresh(quiet: false), "Two refreshes asked for by hand still do not overlap")
        store.endRefresh(quiet: true)
        XCTAssertTrue(store.refreshing, "The quiet one ending does not end the other")
        XCTAssertFalse(store.beginRefresh(quiet: true), "A quiet refresh gives way to one asked for by hand")
        store.endRefresh(quiet: false)
        XCTAssertFalse(store.refreshing)
        XCTAssertFalse(store.fetchingQuotes)
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

    @MainActor func testPriceTypedIntoTheForm() {
        XCTAssertEqual(try PriceAlertsView.price(from: "18.5"), 18.5)
        XCTAssertEqual(try PriceAlertsView.price(from: "1,000,000"), AlertEngine.maxPrice, "The largest price is still taken")
        XCTAssertThrowsError(try PriceAlertsView.price(from: "1000000.01")) { XCTAssertEqual($0.localizedDescription, "價格太大了，請確認後再試。") }
        for text in ["", "0", "-5", "abc"] {
            XCTAssertThrowsError(try PriceAlertsView.price(from: text), text) { XCTAssertEqual($0.localizedDescription, "請輸入大於 0 的價格。") }
        }
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
