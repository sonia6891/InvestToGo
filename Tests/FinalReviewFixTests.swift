import XCTest
import UserNotifications
@testable import ETFToGo

/// The whole-branch review's fixes that live in the app (the ones in PocketCore are tested there; 回測's are in
/// `BacktestClientTests`, the fund companies' in `HoldingsClientTests`, 到價提醒's in `PriceAlertMonitorTests`).
final class FinalReviewFixTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("final-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.appendingPathExtension("holdings").path)
        try? FileManager.default.removeItem(at: directory)
    }

    private var file: URL { directory.appendingPathComponent("p.json") }
    private let now = GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!

    private func snapshot(_ symbol: String, _ date: String) -> ComponentSnapshot {
        ComponentSnapshot(symbol: symbol, date: date, components: [FundComponent(symbol: "2330", name: "台積電", weight: 50)], source: "test")
    }

    // MARK: A5. 組合試算's scenarios

    /// A non-member who picks 保守 in 試算設定 lands on 保守 (the lock card over the preview), not on 基準's figures;
    /// every choice that is the member's wears the crown, in the settings and on the result.
    func testNonMemberLandsOnTheScenarioPicked() {
        for scenario in ComboScenario.allCases {
            XCTAssertEqual(ComboGate.opening(saved: scenario, member: false, fromSettings: true), scenario, "\(scenario) picked in 試算設定")
            XCTAssertEqual(ComboGate.opening(saved: scenario, member: false, fromSettings: false), .base, "Opened any other way a non-member starts on 基準")
            XCTAssertEqual(ComboGate.opening(saved: scenario, member: true, fromSettings: true), scenario)
            XCTAssertEqual(ComboGate.opening(saved: scenario, member: true, fromSettings: false), scenario)
            XCTAssertEqual(ComboGate.crowned(scenario, member: false), scenario != .base, "\(scenario)")
            XCTAssertFalse(ComboGate.crowned(scenario, member: true), "A member sees no crown")
        }
        // 試算設定 opens on 基準 for a non-member whatever was saved: a member's scenario is opened only by picking it.
        XCTAssertEqual(ComboGate.preselected(saved: .conservative, member: false), .base)
        XCTAssertEqual(ComboGate.preselected(saved: .conservative, member: true), .conservative)
        XCTAssertEqual(ComboGate.preselected(saved: .optimistic, member: true), .optimistic)
        XCTAssertEqual(ComboGate.preselected(saved: .stress, member: true), .base, "壓力測試 is not one of the three offered there")
        XCTAssertEqual(ComboGate.memberOnly, "口袋會員專屬")
    }

    // MARK: A6. Game progress in a backup

    /// A phone with no progress takes the backup's: level, streak and the months behind 月報 and 年報 are back.
    @MainActor func testImportRestoresGameProgressOnAFreshPhone() throws {
        let old = PortfolioStore(url: file)
        var holding = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        holding.purchaseDate = now
        try old.save(holding, logBuy: true, now: now)
        try old.updateGame { $0.collected["0050"] = self.now }
        let saved = try XCTUnwrap(old.data.game)
        XCTAssertGreaterThan(saved.xp, 0)
        let backup = try Data(contentsOf: old.export())

        let phone = PortfolioStore(url: directory.appendingPathComponent("new.json"))
        // What a first launch leaves behind: the habit from onboarding, the migrations marked as run.
        try phone.updateGame { $0.habit = .dca; $0.migration = 1; $0.migratedAt = self.now }
        let summary = try phone.importBackup(backup)
        XCTAssertFalse(summary.gameSkipped)
        XCTAssertEqual(summary.message, "匯入完成，匯入前資料已保存於復原副本。")
        XCTAssertEqual(phone.data.game, saved, "Adopted whole")
        XCTAssertEqual(phone.data.game?.xpByMonth.values.reduce(0, +), saved.xp, "xpByMonth agrees with xp")
        let card = PocketReport.make(.yearToDate(2026), portfolio: phone.data, now: now)
        XCTAssertEqual(card.xpEarned, saved.xp, "年報 has the experience again")
        XCTAssertEqual(card.dcaMonths, 1)
        XCTAssertEqual(PortfolioStore(url: directory.appendingPathComponent("new.json")).data.game, saved, "Saved with the records")
        // The same backup again: the progress is the same one, nothing to say.
        XCTAssertFalse(try phone.importBackup(backup).gameSkipped)
        XCTAssertEqual(phone.data.game, saved)
    }

    /// A phone that already has progress keeps it as it is (no merging: that would be a way to earn experience
    /// twice), and the message says the backup's was not imported.
    @MainActor func testImportKeepsThePhonesOwnGameProgress() throws {
        let old = PortfolioStore(url: file)
        var holding = Holding(symbol: "0050", name: "元大台灣50", shares: 1000, unitCost: 50, broker: "", strategy: .saving)
        holding.purchaseDate = now
        try old.save(holding, logBuy: true, now: now)
        let backup = try Data(contentsOf: old.export())

        let phone = PortfolioStore(url: directory.appendingPathComponent("used.json"))
        try phone.updateGame { _ = $0.visitFund("00878", now: self.now) }
        let own = try XCTUnwrap(phone.data.game)
        XCTAssertFalse(own.isFresh)
        let summary = try phone.importBackup(backup)
        XCTAssertTrue(summary.gameSkipped)
        XCTAssertEqual(summary.message, "匯入完成，匯入前資料已保存於復原副本。遊戲進度沒有匯入：這支手機已經有進度。")
        XCTAssertEqual(phone.data.game, own, "Untouched: not a point or a month from the backup")
        XCTAssertEqual(phone.data.holdings.map(\.symbol), ["0050"], "The records themselves are still imported")
        XCTAssertEqual(PortfolioStore.ImportSummary.gameKept, "遊戲進度沒有匯入：這支手機已經有進度。")
    }

    // MARK: B1. The worn skin at a launch on a locked phone

    /// With the records locked the level reads 1: a lapsed member wearing a skin their level earned is not put back
    /// to 黑金 then. The skin is judged once the records are read, on the real level.
    @MainActor func testWornSkinIsNotJudgedWhileRecordsAreLocked() throws {
        let savedSkin = UserDefaults.standard.string(forKey: SkinStore.skinKey)
        defer {
            if let savedSkin { UserDefaults.standard.set(savedSkin, forKey: SkinStore.skinKey) } else { UserDefaults.standard.removeObject(forKey: SkinStore.skinKey) }
            SkinStore.current = SkinStore.shared.skin
        }
        let voxel = Skins.named("voxel")
        guard case .level(let needed) = voxel.unlock else { return XCTFail("像素 unlocks by level") }
        let skins = SkinStore()
        let membership = MembershipStore()
        membership.skins = skins
        membership.checksWornSkin = true
        var locked = true
        var notices: [String] = []
        // What the app wires up: locked records read as level 1.
        membership.level = { locked ? 1 : needed }
        membership.recordsLocked = { locked }
        membership.onLapse = { notices.append($0) }

        skins.select("voxel")
        membership.recordsRead()
        XCTAssertEqual(skins.skin.id, "voxel", "Before StoreKit has answered nothing is judged")
        membership.apply([])
        XCTAssertEqual(skins.skin.id, "voxel", "Not a member, level unknown: the skin stays on while the records are locked")
        XCTAssertTrue(notices.isEmpty)
        locked = false
        membership.recordsRead()
        XCTAssertEqual(skins.skin.id, "voxel", "The records say the level is reached: still worn")
        XCTAssertTrue(notices.isEmpty)

        // A member skin worn by someone whose membership lapsed is still taken off, once the records are read.
        locked = true
        skins.select("stitch")
        membership.apply([])
        XCTAssertEqual(skins.skin.id, "stitch")
        locked = false
        membership.recordsRead()
        XCTAssertEqual(skins.skin.id, "blackgold")
        XCTAssertEqual(notices, [MembershipStore.lapseNotice])
    }

    // MARK: B2. A holdings history file that could not be read

    /// The records open but the history file beside them does not (the phone locked between the two reads). The
    /// history in memory is then empty; saving it would wipe the days on file. It is left alone until it can be
    /// read, and then what it holds is kept together with what was added meanwhile.
    @MainActor func testLockedHistoryFileIsNotSavedOver() throws {
        let side = file.appendingPathExtension("holdings")
        let first = PortfolioStore(url: file)
        for day in 1...3 { try first.saveComponents(snapshot("0050", "2026-11-0\(day)")) }
        try first.saveComponents(snapshot("00878", "2026-11-03"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: side.path)
        if (try? Data(contentsOf: side)) != nil { throw XCTSkip("This machine reads the file whatever its permissions") }

        let store = PortfolioStore(url: file)
        XCTAssertFalse(store.recordsLocked, "The records themselves were read")
        XCTAssertTrue(store.componentHistoryLocked)
        XCTAssertNil(store.message)
        XCTAssertTrue(store.componentHistory(for: "0050").isEmpty)
        // A save while the file cannot be read: the records are saved, the history file is not touched.
        try store.saveComponents(snapshot("0050", "2026-11-10"))
        XCTAssertTrue(store.componentHistoryLocked)
        XCTAssertEqual(store.data.components?["0050"]?.date, "2026-11-10")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: side.path)
        let onFile = try JSONDecoder().decode([String: [ComponentSnapshot]].self, from: Data(contentsOf: side))
        XCTAssertEqual(Set((onFile["0050"] ?? []).map(\.date)), ["2026-11-01", "2026-11-02", "2026-11-03"], "Nothing was saved over it")
        XCTAssertEqual(onFile["00878"]?.map(\.date), ["2026-11-03"])

        // The next save reads the file first: its days and the two added since are all kept.
        try store.saveComponents(snapshot("0050", "2026-11-11"))
        XCTAssertFalse(store.componentHistoryLocked)
        let expected = ["2026-11-11", "2026-11-10", "2026-11-03", "2026-11-02", "2026-11-01"]
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), expected)
        XCTAssertEqual(store.componentHistory(for: "00878").map(\.date), ["2026-11-03"])
        let reopened = PortfolioStore(url: file)
        XCTAssertEqual(reopened.componentHistory(for: "0050").map(\.date), expected, "On file")
        XCTAssertEqual(reopened.componentHistory(for: "00878").map(\.date), ["2026-11-03"])
    }

    /// Coming back to the app reads a history file that was locked at launch, without waiting for a save.
    @MainActor func testLockedHistoryFileIsReadOnReturn() throws {
        let side = file.appendingPathExtension("holdings")
        let first = PortfolioStore(url: file)
        try first.saveComponents(snapshot("0050", "2026-11-01"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: side.path)
        if (try? Data(contentsOf: side)) != nil { throw XCTSkip("This machine reads the file whatever its permissions") }
        let store = PortfolioStore(url: file)
        var redone = 0
        store.onRecordsRead = { _ in redone += 1 }
        XCTAssertTrue(store.componentHistoryLocked)
        XCTAssertTrue(store.reloadIfLocked(), "The records are not locked")
        XCTAssertTrue(store.componentHistoryLocked, "Still not to be opened")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: side.path)
        XCTAssertTrue(store.reloadIfLocked())
        XCTAssertFalse(store.componentHistoryLocked)
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), ["2026-11-01"])
        XCTAssertEqual(redone, 0, "The records were read at launch: their launch steps are not redone")
        // A file that is simply not there is not a locked one.
        let fresh = PortfolioStore(url: directory.appendingPathComponent("fresh.json"))
        XCTAssertFalse(fresh.componentHistoryLocked)
        XCTAssertNoThrow(try fresh.saveComponents(snapshot("0050", "2026-11-01")))
        XCTAssertEqual(PortfolioStore(url: directory.appendingPathComponent("fresh.json")).componentHistory(for: "0050").count, 1)
    }

    // MARK: B6, B8, B10, B12, B13. Copy

    @MainActor func testCopy() {
        XCTAssertEqual(MemberLockCopy.sample, "示意畫面，非真實資料", "Every lock card says its preview is a sample")
        XCTAssertEqual(ReportCardView.levelLabel, "目前等級", "A past period's card shows today's level, and says so")
        XCTAssertEqual(ReportCardView.brand, "投資袋著走")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, ReportCardView.brand, "The app's own name")
        XCTAssertEqual(ActiveTrackingView.supported, "目前支援元大、國泰、富邦、群益、復華、中信六家投信。")
        XCTAssertEqual(Issuer.allCases.count, 6, "The six it names are the six the app reads")
        for word in ["到價提醒", "成分股紀錄", "遊戲進度", "持有", "配息", "交易", "收藏"] {
            XCTAssertTrue(BackupView.backupSubtitle.contains(word), "\(word) is in a backup and in its description")
        }
        XCTAssertTrue(BackupView.backupSubtitle.contains("不含行情金鑰"))
    }

    /// B12. What the description lists is what a backup carries.
    @MainActor func testBackupHoldsWhatItsDescriptionSays() throws {
        let store = PortfolioStore(url: file)
        try store.addAlert(symbol: "0050", above: true, price: 200)
        try store.saveComponents(snapshot("0050", "2026-11-13"))
        try store.updateGame { _ = $0.visitFund("0050", now: self.now) }
        let backup = try Portfolio.decodeBackup(Data(contentsOf: store.export()))
        XCTAssertEqual(backup.alerts?.map(\.symbol), ["0050"])
        XCTAssertEqual(backup.componentHistory?["0050"]?.map(\.date), ["2026-11-13"])
        XCTAssertNotNil(backup.game)
        XCTAssertNil(backup.histories, "Price histories are left out, as it says")
    }

    // MARK: B9. Restored alerts and the notification permission

    @MainActor func testRestoredAlertsAskForPermissionOnce() {
        XCTAssertTrue(PriceAlertsView.asksPermissionOnAppear(status: .notDetermined, hasAlerts: true, testing: false), "Alerts from a backup, iOS never asked")
        XCTAssertFalse(PriceAlertsView.asksPermissionOnAppear(status: .notDetermined, hasAlerts: false, testing: false), "No alert yet: asking waits for the first one")
        XCTAssertFalse(PriceAlertsView.asksPermissionOnAppear(status: .notDetermined, hasAlerts: true, testing: true), "Never under --ui-testing")
        for status in [UNAuthorizationStatus.denied, .authorized, .provisional] {
            XCTAssertFalse(PriceAlertsView.asksPermissionOnAppear(status: status, hasAlerts: true, testing: false), "Already answered: not asked again")
        }
    }

    // MARK: C. Nothing that is only planned is on screen

    @MainActor func testUpcomingContentIsHidden() {
        XCTAssertFalse(Upcoming.visible)
        XCTAssertEqual(MemberView.Plan.shown(), [.free, .pocket], "The paywall lists the two plans there are")
        XCTAssertEqual(MemberView.Plan.shown(upcoming: true), MemberView.Plan.allCases, "會員＋AI is still in the code")
        XCTAssertFalse(MemberView.Plan.shown().contains { $0.comingSoon })
        XCTAssertFalse(Achievements.shown().contains { $0.comingSoon })
        // 口袋會員's own line promises nothing that is not in the app.
        XCTAssertFalse(MemberView.Plan.pocket.detail.contains("AI"))
    }
}
