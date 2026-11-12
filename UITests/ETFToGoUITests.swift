import XCTest
import UIKit

final class ETFToGoUITests: XCTestCase {
    func testOTCCatalogAndRestoredResearchNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--open", "find"]; app.launch()
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("00679B\n")
        let fund = app.staticTexts["元大美債20年"]; XCTAssertTrue(fund.waitForExistence(timeout: 5)); fund.tap()
        XCTAssertTrue(app.buttons["持股"].waitForExistence(timeout: 5))
        app.buttons["持股"].tap()
        XCTAssertTrue(app.buttons["更新成分股"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["尚無成分資料"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "restored-components"; attachment.lifetime = .keepAlways; add(attachment)
        quickPick(app, "tools")
        XCTAssertTrue(app.buttons["tool-broker"].waitForExistence(timeout: 5))
        app.buttons["tool-broker"].tap()
        XCTAssertTrue(app.textFields["broker-import-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["選擇庫存 CSV"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"] + arguments; app.launch(); return app
    }
    /// Switches feature with the bottom bar's quick pick.
    private func quickPick(_ app: XCUIApplication, _ feature: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["bar-quick"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The bottom bar has the quick-pick button", file: file, line: line)
        button.tap()
        let disc = app.buttons["quick-\(feature)"]
        XCTAssertTrue(disc.waitForExistence(timeout: 5), "quick-\(feature) pops out", file: file, line: line)
        disc.tap()
    }
    /// Scrolls until a control further down a page is clear of the bottom bar, then taps it.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) can be reached", file: file, line: line)
        element.tap()
    }
    private func waitForLabel(_ element: XCUIElement, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: 5), .completed, "Expected \(label), got \(element.exists ? element.label : "nothing")", file: file, line: line)
    }
    func testAnnualFeesAndHistoryNavigation() {
        let app=XCUIApplication(); app.launchArguments=["--ui-testing","--reset","--open","find"]; app.launch()
        let search=app.textFields["fund-search"]; XCTAssertTrue(search.waitForExistence(timeout:10))
        search.tap(); search.typeText("0050\n"); app.staticTexts["元大台灣50"].tap()
        XCTAssertTrue(app.buttons["資訊"].waitForExistence(timeout:5))
        app.buttons["資訊"].tap()
        XCTAssertTrue(app.staticTexts["annual-fee-heading"].waitForExistence(timeout:5))
        let totalFee = app.descendants(matching: .any).matching(identifier: "annual-fee-total").firstMatch
        XCTAssertTrue(totalFee.waitForExistence(timeout: 5))
        XCTAssertEqual(totalFee.label, "2025 年總費用率")
        XCTAssertEqual(totalFee.value as? String, "0.22%")
        capture(app,"annual-fees-0050")
        app.buttons["走勢"].tap()
        XCTAssertTrue(app.buttons["更新歷史績效"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["尚無歷史資料"].exists); capture(app,"history-empty-state")
    }
    func testAllFeaturesAndSearch() {
        let app = launch(["--open", "find"])
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); capture(app,"screen-find")
        search.tap(); search.typeText("0050\n")
        XCTAssertTrue(app.staticTexts["元大台灣50"].exists)
        XCTAssertFalse(app.staticTexts["國泰永續高股息"].exists)
        quickPick(app, "pocket")
        XCTAssertTrue(app.buttons["pocket-add"].waitForExistence(timeout: 5)); capture(app,"screen-pocket")
        quickPick(app, "dividends")
        XCTAssertTrue(app.buttons["dividends-log"].waitForExistence(timeout: 5)); capture(app,"screen-dividends")
        quickPick(app, "tools")
        XCTAssertTrue(app.buttons["tool-backup"].waitForExistence(timeout: 5)); capture(app,"screen-tools")
    }
    func testDiscoverIsETFOnlyAndComboRuns() {
        let app = launch(["--open", "find"])
        let search = app.textFields["fund-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["個股"].exists, "ETF only: no stock segment in 找 ETF")
        search.tap(); search.typeText("2317\n")
        XCTAssertFalse(app.staticTexts["鴻海"].waitForExistence(timeout: 3), "Stocks are not searchable"); capture(app, "etf-only-search")
        quickPick(app, "tools")
        XCTAssertTrue(app.buttons["tool-combo"].waitForExistence(timeout: 5)); reveal(app, app.buttons["tool-combo"])
        XCTAssertTrue(app.buttons["combo-settings"].waitForExistence(timeout: 5)); capture(app, "combo")
        reveal(app, app.buttons["combo-settings"])
        XCTAssertTrue(app.textFields["combo-monthly"].waitForExistence(timeout: 5)); capture(app, "combo-settings")
        // 開始試算 sits at the end of the page: it must scroll clear of the bottom bar and run.
        reveal(app, app.buttons["combo-run"])
        XCTAssertTrue(app.navigationBars["試算結果"].waitForExistence(timeout: 5)); capture(app, "combo-result")
    }
    /// The pocket's own search opens 找 ETF with the field focused, the watchlist is a tap away, and once there is a
    /// holding the combined simulation opens from the pocket.
    func testPocketSearchWatchlistAndCombo() {
        let app = launch(["--open", "pocket"])
        XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout: 10)); capture(app, "home-empty")
        app.buttons["home-search"].tap()
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The pocket's search opens 找 ETF")
        waitForLabel(app.staticTexts["bar-title"], "找 ETF")
        let done = app.buttons["完成搜尋"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The search focuses the field")
        done.tap()
        quickPick(app, "pocket")
        XCTAssertTrue(app.buttons["home-watchlist"].waitForExistence(timeout: 5))
        app.buttons["home-watchlist"].tap()
        XCTAssertTrue(app.navigationBars["我的自選"].waitForExistence(timeout: 5), "The watchlist opens from the pocket")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        addHolding(app)
        reveal(app, app.buttons["home-combo"])
        XCTAssertTrue(app.buttons["combo-settings"].waitForExistence(timeout: 5), "The combined simulation opens from the pocket")
    }
    /// 「＋ 加一檔」 on the pocket page, filled in and saved; back on the pocket page afterwards.
    private func addHolding(_ app: XCUIApplication, broker: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let add = app.buttons["pocket-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "The pocket has 「＋ 加一檔」", file: file, line: line)
        reveal(app, add, file: file, line: line)
        let symbol = app.textFields["holding-symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5), "「＋ 加一檔」 opens the holding form", file: file, line: line)
        symbol.tap(); symbol.typeText("0050")
        let name = app.textFields["holding-name"]
        if (name.value as? String) == "名稱（清單沒有時填寫）" { name.tap(); name.typeText("Test ETF") }
        app.textFields["holding-shares"].tap(); app.textFields["holding-shares"].typeText("1000")
        app.textFields["holding-cost"].tap(); app.textFields["holding-cost"].typeText("50")
        if let broker { app.textFields["holding-broker"].tap(); app.textFields["holding-broker"].typeText(broker) }
        app.buttons["save-holding"].tap()
        XCTAssertTrue(app.buttons["save-holding"].waitForNonExistence(timeout: 5), "The form closes after saving", file: file, line: line)
    }
    func testHoldingSurvivesRelaunch() {
        let app = launch(["--open", "pocket"])
        addHolding(app, broker: "Test Broker")
        let total = app.staticTexts["portfolio-value"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "The pocket shows its total once it holds an ETF")
        XCTAssertTrue(total.label.hasPrefix("NT$ "), "The total is the saved holding's value: \(total.label)")
        XCTAssertNotEqual(total.label, "NT$ —", "The holding is priced")
        app.terminate(); app.launchArguments = ["--ui-testing", "--open", "pocket"]; app.launch()
        XCTAssertTrue(app.staticTexts["portfolio-value"].waitForExistence(timeout: 10), "The holding is still in the pocket after a relaunch")
        XCTAssertTrue(app.staticTexts["0050"].exists, "The pocket lists the holding")
        reveal(app, app.buttons["holdings-trades"])
        XCTAssertTrue(app.staticTexts["買進"].waitForExistence(timeout: 5), "Saving a new holding is recorded in the trade log")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app, app.buttons["holdings-allocation"])
        XCTAssertTrue(app.staticTexts["券商帳戶"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Broker"].exists)
    }
    /// The skin kit's component sheet in each skin, to compare with the four-skin canvas.
    func testSkinKitSheet() {
        for id in ["blackgold", "voxel", "stitch", "sketch"] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--skin", id, "--open", "skinKit"]; app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["skinkit-root"].waitForExistence(timeout: 10), "\(id): the skin kit sheet opens")
            sleep(1)
            capture(app, "skinkit-\(id)")
            app.terminate()
        }
    }

    // MARK: Lobby and quick pick (spec 4.2, 4.3)

    func testLobbyEntriesAndBack() {
        let app = launch(["--demo-streak", "12"])
        XCTAssertTrue(app.descendants(matching: .any)["連續定投 12 個月"].waitForExistence(timeout: 10), "The hero shows the streak")
        XCTAssertEqual(app.descendants(matching: .any)["lobby-xp"].value as? String, "0 經驗")
        sleep(1); capture(app, "lobby-streak-12")
        let pages: [(String, XCUIElement, String)] = [
            ("lobby-find", app.textFields["fund-search"], "找 ETF"),
            ("lobby-dividends", app.buttons["dividends-log"], "配息"),
            ("lobby-pocket", app.buttons["pocket-add"], "口袋"),
            ("lobby-tools", app.buttons["tool-backup"], "工具"),
            ("lobby-achievements", app.staticTexts["bar-title"], "成就"),
        ]
        for (entry, marker, title) in pages {
            let button = app.buttons[entry]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(entry) is in the lobby")
            button.tap()
            XCTAssertTrue(marker.waitForExistence(timeout: 5), "\(entry) opens its page")
            waitForLabel(app.staticTexts["bar-title"], title)
            app.buttons["bar-lobby"].tap()
            XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5), "\(entry): ‹ 大廳 returns to the lobby")
            XCTAssertTrue(app.buttons["bar-lobby"].waitForNonExistence(timeout: 5), "\(entry): the lobby has no bottom bar")
        }
        app.descendants(matching: .any)["連續定投 12 個月"].tap()
        XCTAssertTrue(app.staticTexts["最長紀錄 12 個月"].waitForExistence(timeout: 5), "The number opens the DCA history")
        capture(app, "dca-history")
    }

    func testQuickPickSwitchesEveryFeature() {
        let app = launch(["--demo-streak", "12", "--open", "find"])
        XCTAssertTrue(app.textFields["fund-search"].waitForExistence(timeout: 10))
        waitForLabel(app.staticTexts["bar-title"], "找 ETF")
        let titles = ["dividends": "配息", "pocket": "口袋", "tools": "工具", "achievements": "成就", "find": "找 ETF"]
        for feature in ["dividends", "pocket", "tools", "achievements", "find"] {
            app.buttons["bar-quick"].tap()
            let disc = app.buttons["quick-\(feature)"]
            XCTAssertTrue(disc.waitForExistence(timeout: 5), "quick-\(feature) pops out")
            if feature == "dividends" { sleep(1); capture(app, "quick-pick-open") }
            disc.tap()
            waitForLabel(app.staticTexts["bar-title"], titles[feature]!)
        }
        app.buttons["bar-quick"].tap()
        for feature in titles.keys { XCTAssertTrue(app.buttons["quick-\(feature)"].waitForExistence(timeout: 5), "quick-\(feature) is shown") }
        app.buttons["bar-quick"].tap()
        for feature in titles.keys { XCTAssertTrue(app.buttons["quick-\(feature)"].waitForNonExistence(timeout: 5), "quick-\(feature) folds away") }
    }

    func testNewbieLobby() {
        let app = launch([])
        XCTAssertTrue(app.staticTexts["今天開始"].waitForExistence(timeout: 10), "A newbie starts today")
        XCTAssertTrue(app.staticTexts["設定第一筆定投"].exists, "The newbie quest is listed")
        XCTAssertFalse(app.descendants(matching: .any)["連續定投 0 個月"].exists, "Never a bare 0")
        sleep(1); capture(app, "lobby-newbie")
    }

    func testHugeStreakFits() {
        for skin in ["blackgold", "voxel", "stitch", "sketch"] {
            let app = launch(["--demo-streak", "120", "--skin", skin])
            let hero = app.descendants(matching: .any)["連續定投 120 個月"]
            XCTAssertTrue(hero.waitForExistence(timeout: 10), "\(skin): the hero shows 120")
            let window = app.windows.firstMatch.frame
            XCTAssertLessThanOrEqual(hero.frame.width, window.width, "\(skin): 120 fits the width")
            XCTAssertGreaterThanOrEqual(hero.frame.minX, window.minX, "\(skin): 120 starts on screen")
            XCTAssertLessThanOrEqual(hero.frame.maxX, window.maxX, "\(skin): 120 ends on screen")
            capture(app, "lobby-120-\(skin)")
            app.terminate()
        }
    }

    func testNoTabBar() {
        let lobby = launch([])
        XCTAssertTrue(lobby.buttons["lobby-find"].waitForExistence(timeout: 10))
        XCTAssertEqual(lobby.tabBars.count, 0, "No tab bar in the lobby")
        lobby.terminate()
        let app = launch(["--open", "find"])
        XCTAssertTrue(app.textFields["fund-search"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.count, 0)
    }

    /// Ruling R21: scrolling a feature's list back up never leaves for the lobby; only a pull from the very top does.
    func testScrollUpDoesNotLeaveFeature() {
        let app = launch(["--open", "find"])
        XCTAssertTrue(app.textFields["fund-search"].waitForExistence(timeout: 10))
        for _ in 0..<4 { app.swipeUp() }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)))
        sleep(1)
        XCTAssertTrue(app.buttons["bar-lobby"].exists, "Still in 找 ETF: the bottom bar is there")
        XCTAssertFalse(app.buttons["lobby-find"].exists, "Scrolling up did not return to the lobby")
    }

    // MARK: 找 ETF, ETF detail and dex card (spec 5.4–5.6)

    func testFindDetailAndDex() {
        let app = launch(["--open", "find"])
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        waitForLabel(app.staticTexts["bar-title"], "找 ETF")

        // 高股息 leaves only high-dividend funds, and every row shows its move as an arrow plus a percentage.
        app.buttons["高股息"].tap()
        XCTAssertTrue(app.staticTexts["元大高股息"].waitForExistence(timeout: 5), "A high-dividend fund is listed")
        XCTAssertFalse(app.staticTexts["元大台灣50"].exists, "A market-cap fund is filtered out")
        let changes = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'fund-change-'")).allElementsBoundByIndex
        XCTAssertGreaterThan(changes.count, 3, "The filtered rows show their change")
        // A move is ▲ or ▼ plus its size; only an unchanged price reads "－ 0.00%" (there is no direction to show).
        let move = NSPredicate(format: "SELF MATCHES %@", "^[▲▼] [0-9]+\\.[0-9]{2}%$")
        // The shown text is the element's value; its label is the spoken 上漲 / 下跌 / 持平.
        let shown = changes.map { ($0.identifier, $0.value as? String ?? "", $0.label) }
        for (id, text, spoken) in shown {
            XCTAssertTrue(move.evaluate(with: text) || text == "－ 0.00%", "\(id) shows ▲ or ▼ and a percentage: \(text)")
            XCTAssertTrue(["上漲 ", "下跌 ", "持平 "].contains { spoken.hasPrefix($0) }, "\(id) is spoken as a direction: \(spoken)")
        }
        XCTAssertTrue(shown.contains { move.evaluate(with: $0.1) }, "At least one row moved")
        capture(app, "find-high-dividend")

        // Search 0050 and open it: the code, the four tabs and, the first time, the dex toast.
        app.buttons["全部"].tap()
        search.tap(); search.typeText("0050\n")
        let row = app.staticTexts["元大台灣50"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '收進圖鑑'")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "The first visit collects the card")
        XCTAssertEqual(toast.label, "收進圖鑑 +30 經驗")
        XCTAssertTrue(app.staticTexts["detail-code"].exists)
        XCTAssertEqual(app.staticTexts["detail-code"].label, "0050")
        for tab in ["走勢", "持股", "配息", "資訊"] { XCTAssertTrue(app.buttons[tab].exists, "The detail has the \(tab) tab") }
        capture(app, "detail-0050")

        // The dex card: five block bars, the fee and history ones named as facts.
        app.buttons["圖鑑卡"].tap()
        for bar in ["fee", "size", "yield", "volatility", "history"] {
            XCTAssertTrue(app.descendants(matching: .any)["dex-bar-\(bar)"].waitForExistence(timeout: 5), "dex-bar-\(bar) is on the card")
        }
        XCTAssertTrue(app.descendants(matching: .any)["dex-bar-fee"].label.hasPrefix("低費用"))
        XCTAssertTrue(app.descendants(matching: .any)["dex-bar-history"].label.hasPrefix("上市時間"))
        XCTAssertTrue(app.buttons["PK 比一比"].exists)
        XCTAssertTrue(app.buttons["加入口袋"].exists)
        capture(app, "dex-0050")

        // Back to the list and in again: already collected, so no toast.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["圖鑑卡"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["detail-code"].waitForExistence(timeout: 5))
        XCTAssertFalse(toast.waitForExistence(timeout: 3), "A collected card does not toast again")
    }

    /// 找 ETF, the detail and the dex card in each skin, to compare with the canvas.
    func testFindDetailAndDexInEverySkin() {
        for id in ["blackgold", "voxel", "stitch", "sketch"] {
            let app = launch(["--skin", id, "--open", "find"])
            let search = app.textFields["fund-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "\(id): 找 ETF opens")
            sleep(1); capture(app, "find-\(id)")
            search.tap(); search.typeText("0050\n")
            let row = app.staticTexts["元大台灣50"]
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
            XCTAssertTrue(app.buttons["圖鑑卡"].waitForExistence(timeout: 5), "\(id): the detail opens")
            sleep(3); capture(app, "detail-\(id)")
            app.buttons["圖鑑卡"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["dex-bar-fee"].waitForExistence(timeout: 5), "\(id): the dex card opens")
            sleep(1); capture(app, "dex-\(id)")
            app.terminate()
        }
    }

    /// The lobby and the quick pick in each skin, to compare with the canvas.
    func testLobbyAndQuickPickInEverySkin() {
        for id in ["blackgold", "voxel", "stitch", "sketch"] {
            let app = launch(["--demo-streak", "12", "--demo-level", "7", "--skin", id])
            XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 10), "\(id): the lobby opens")
            sleep(2); capture(app, "lobby-\(id)")
            app.buttons["lobby-find"].tap()
            XCTAssertTrue(app.buttons["bar-quick"].waitForExistence(timeout: 5)); app.buttons["bar-quick"].tap()
            XCTAssertTrue(app.buttons["quick-pocket"].waitForExistence(timeout: 5)); sleep(1); capture(app, "quickpick-\(id)")
            app.terminate()
        }
    }

    // MARK: 口袋 and 配息 (spec 5.7, 5.8)

    /// Ruling R15: a newbie's pocket and dividends show the object, one sentence and one button, never NT$ 0.
    func testNewbiePocketAndDividendsHaveNoZeroHero() {
        let zero = NSPredicate(format: "label CONTAINS 'NT$ 0'")
        let pocket = launch(["--open", "pocket"])
        XCTAssertTrue(pocket.buttons["＋ 加一檔"].waitForExistence(timeout: 10), "The empty pocket offers 「＋ 加一檔」")
        XCTAssertTrue(pocket.staticTexts["pocket-newbie"].exists, "The empty pocket explains itself in a sentence")
        XCTAssertFalse(pocket.staticTexts["portfolio-value"].exists, "No total before there is anything to add up")
        XCTAssertEqual(pocket.descendants(matching: .any).matching(zero).count, 0, "No NT$ 0 in the empty pocket")
        sleep(1); capture(pocket, "pocket-newbie")
        pocket.terminate()
        let dividends = launch(["--open", "dividends"])
        XCTAssertTrue(dividends.buttons["記一筆配息"].waitForExistence(timeout: 10), "Dividends offer 「記一筆配息」")
        XCTAssertTrue(dividends.staticTexts["dividends-newbie"].exists, "Empty dividends explain themselves in a sentence")
        XCTAssertFalse(dividends.staticTexts["dividends-total"].exists, "No total before anything was received")
        XCTAssertEqual(dividends.descendants(matching: .any).matching(zero).count, 0, "No NT$ 0 on the empty dividends page")
        sleep(1); capture(dividends, "dividends-newbie")
    }

    /// Logging a dividend earns the flat 記一筆配息 experience (+20), whatever its amount, and plays the coin drop.
    func testLogDividendGivesXP() {
        let app = launch([])
        let xp = app.descendants(matching: .any)["lobby-xp"]
        XCTAssertTrue(xp.waitForExistence(timeout: 10))
        // A first visit settles any quest that viewing dividends finishes, so the difference below is the log alone.
        app.buttons["lobby-dividends"].tap()
        let log = app.buttons["dividends-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        app.buttons["bar-lobby"].tap()
        XCTAssertTrue(xp.waitForExistence(timeout: 5))
        let before = Int((xp.value as? String ?? "").split(separator: " ").first ?? "") ?? -1
        XCTAssertGreaterThanOrEqual(before, 0, "The XP bar reads \(String(describing: xp.value))")
        app.buttons["lobby-dividends"].tap()
        XCTAssertTrue(log.waitForExistence(timeout: 5)); log.tap()
        let symbol = app.textFields["dividend-symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5), "「記一筆配息」 opens the dividend form")
        symbol.tap(); symbol.typeText("0050")
        app.textFields["dividend-shares"].tap(); app.textFields["dividend-shares"].typeText("1000")
        app.textFields["dividend-per-share"].tap(); app.textFields["dividend-per-share"].typeText("1")
        capture(app, "dividend-form")
        app.buttons["save-dividend"].tap()
        // The toast stays a few seconds; look for it first, then check the form is gone.
        let toast = app.staticTexts["dividend-xp-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "Back on 配息, the reward is shown")
        XCTAssertFalse(app.buttons["save-dividend"].exists, "The form closes after saving")
        XCTAssertEqual(toast.label, "記一筆配息 +20 經驗")
        capture(app, "dividend-logged")
        app.buttons["bar-lobby"].tap()
        XCTAssertTrue(xp.waitForExistence(timeout: 5))
        let after = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(before + 20) 經驗"), object: xp)
        XCTAssertEqual(XCTWaiter().wait(for: [after], timeout: 5), .completed, "XP went from \(before) to \(String(describing: xp.value))")
    }

    /// 口袋 and 配息 with sample holdings in each skin, to compare with the canvas. A loss is shown honestly: ▼ and
    /// its size, spoken as 下跌.
    func testPocketAndDividendsInEverySkin() {
        for id in ["blackgold", "voxel", "stitch", "sketch"] {
            let app = launch(["--demo-pocket", "--skin", id, "--open", "pocket"])
            let total = app.staticTexts["portfolio-value"]
            XCTAssertTrue(total.waitForExistence(timeout: 10), "\(id): the pocket shows its total")
            XCTAssertTrue(total.label.hasPrefix("NT$ "), "\(id): the total is in NT$: \(total.label)")
            XCTAssertNotEqual(total.label, "NT$ —", "\(id): the sample holdings are priced")
            XCTAssertTrue(app.staticTexts["我的口袋 · 4 檔"].exists, "\(id): the pocket counts its ETFs")
            let loss = app.staticTexts["pocket-change-00679B"]
            XCTAssertTrue(loss.waitForExistence(timeout: 5), "\(id): the losing holding is listed")
            XCTAssertTrue((loss.value as? String ?? "").hasPrefix("▼ "), "\(id): a loss shows ▼: \(String(describing: loss.value))")
            XCTAssertTrue(loss.label.hasPrefix("下跌 "), "\(id): a loss is spoken as 下跌: \(loss.label)")
            sleep(1); capture(app, "pocket-\(id)")
            app.swipeUp(); sleep(1); capture(app, "pocket-lower-\(id)")
            quickPick(app, "dividends")
            let received = app.staticTexts["dividends-total"]
            XCTAssertTrue(received.waitForExistence(timeout: 5), "\(id): dividends show this year's total")
            XCTAssertTrue(received.label.hasPrefix("NT$ "), "\(id): \(received.label)")
            XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'dividend-month-'")).count, 12, "\(id): twelve month checks")
            sleep(1); capture(app, "dividends-\(id)")
            app.swipeUp(); sleep(1); capture(app, "dividends-lower-\(id)")
            app.terminate()
        }
    }

    // MARK: Tools, membership and skins (spec 5.9, 5.10, 5.13)

    /// 工具 → 會員・換膚 → 換膚.
    private func openSkins(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let member = app.buttons["tool-member"]
        XCTAssertTrue(member.waitForExistence(timeout: 10), "工具 has 會員・換膚", file: file, line: line)
        reveal(app, member, file: file, line: line)
        let skins = app.buttons["member-skins"]
        XCTAssertTrue(skins.waitForExistence(timeout: 5), "會員 opens with a way to 換膚", file: file, line: line)
        sleep(1); capture(app, "member")
        reveal(app, skins, file: file, line: line)
        XCTAssertTrue(app.buttons["skin-apply"].waitForExistence(timeout: 5), "換膚 opens the carousel", file: file, line: line)
    }
    private func waitForLabel(_ element: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: 5), .completed, "Expected …\(text)…, got \(element.exists ? element.label : "nothing")", file: file, line: line)
    }
    /// The screenshot's colour at a point given as fractions of the screen, as 0xRRGGBB.
    private func pixel(_ app: XCUIApplication, _ at: CGVector) -> UInt32 {
        guard let image = app.screenshot().image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return 0 }
        let x = min(image.width - 1, Int(CGFloat(image.width) * at.dx)), y = min(image.height - 1, Int(CGFloat(image.height) * at.dy))
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { bytes.deallocate() }
        bytes.initialize(repeating: 0, count: 4)
        guard let context = CGContext(data: bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        // Core Graphics counts y from the bottom: move the wanted pixel onto the 1×1 canvas.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
    }
    private func sameColour(_ a: UInt32, _ b: UInt32) -> Bool {
        for shift: UInt32 in [16, 8, 0] {
            let x = Int((a >> shift) & 0xFF), y = Int((b >> shift) & 0xFF)
            if abs(x - y) > 3 { return false }
        }
        return true
    }

    /// A label that is only a figure, such as 「12」 or 「1,280」; 「n / 4」 and 「LV.n」 are allowed.
    private func isBareNumber(_ label: String) -> Bool {
        let text = label.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text.contains("/") || text.hasPrefix("LV") { return false }
        let allowed = Set(",.+-−% ")
        for character in text where !character.isNumber && !allowed.contains(character) { return false }
        return true
    }

    func testSkinCarousel() {
        let app = launch(["--demo-level", "7", "--open", "tools"])
        sleep(1); capture(app, "tools")
        openSkins(app)
        let status = app.descendants(matching: .any)["skin-status"], apply = app.buttons["skin-apply"]
        let worn = app.descendants(matching: .any)["skin-card-blackgold"]
        XCTAssertTrue(worn.exists, "The carousel has the black-gold card")
        XCTAssertEqual(worn.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 12, "The carousel opens centred on the skin being worn")
        waitForLabel(status, containing: "使用中")
        waitForLabel(apply, "← 滑動試穿 →")
        sleep(1); capture(app, "skins-blackgold")
        for id in ["voxel", "blackgold", "stitch", "sketch"] { XCTAssertTrue(app.buttons["skin-badge-\(id)"].exists, "\(id) has a style badge") }
        app.buttons["skin-badge-stitch"].tap()
        waitForLabel(status, containing: "會員")
        waitForLabel(apply, "看會員")
        app.buttons["skin-badge-voxel"].tap()
        waitForLabel(status, containing: "LV.10")
        waitForLabel(apply, "去升級")
        app.buttons["skin-badge-sketch"].tap()
        waitForLabel(status, containing: "已解鎖")
        waitForLabel(apply, "換上這套")
        sleep(1); capture(app, "skins-sketch")
        apply.tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5), "換上這套 goes back to the lobby")
        sleep(2); capture(app, "lobby-after-sketch")
        let points = [CGVector(dx: 0.5, dy: 0.035), CGVector(dx: 0.5, dy: 0.15), CGVector(dx: 0.5, dy: 0.25)]
        let colours = points.map { pixel(app, $0) }
        XCTAssertGreaterThanOrEqual(colours.filter { sameColour($0, 0xFAF8F3) }.count, 2,
                                    "The lobby is on sketch paper: \(colours.map { String(format: "%06X", $0) })")
    }

    /// The carousel cards show no figures (spec 5.13): no label on the page is a bare number.
    func testCarouselShowsNoNumbers() {
        let app = launch(["--demo-level", "7", "--demo-streak", "12", "--open", "tools"])
        openSkins(app)
        for id in ["voxel", "blackgold", "stitch", "sketch"] {
            app.buttons["skin-badge-\(id)"].tap(); sleep(1)
            let labels: [String] = app.staticTexts.allElementsBoundByIndex.map { $0.label }
            let bare = labels.filter(isBareNumber)
            XCTAssertEqual(bare, [], "\(id): no bare numbers on the skin page")
            // Cards and style badges carry no figures at all; only 「LV.n」 and 「n / 4」 may hold digits.
            let tagged = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'skin-card-' OR identifier BEGINSWITH 'skin-badge-'"))
                .allElementsBoundByIndex.map { $0.label }
            XCTAssertFalse(tagged.isEmpty, "\(id): cards and badges are on the page")
            let withDigits = tagged.filter(hasFiguresBesidesLevels)
            XCTAssertEqual(withDigits, [], "\(id): no figures on cards or badges")
        }
    }

    /// Digits left after removing 「LV.n」 and 「n / m」.
    private func hasFiguresBesidesLevels(_ label: String) -> Bool {
        let stripped = label
            .replacingOccurrences(of: "LV\\.\\d+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\d+ / \\d+", with: "", options: .regularExpression)
        return stripped.contains { $0.isNumber }
    }

    private func isDark(_ colour: UInt32) -> Bool {
        let red = Int((colour >> 16) & 0xFF), green = Int((colour >> 8) & 0xFF), blue = Int(colour & 0xFF)
        return red < 0x50 && green < 0x50 && blue < 0x50
    }

    /// Holding a card only previews: the worn skin and the app stay as they were.
    func testTryOnChangesNothing() {
        let app = launch(["--demo-level", "7", "--open", "skins"])
        let status = app.descendants(matching: .any)["skin-status"]
        XCTAssertTrue(app.buttons["skin-apply"].waitForExistence(timeout: 10), "換膚 opens")
        waitForLabel(status, containing: "使用中")
        app.buttons["skin-badge-sketch"].tap()
        waitForLabel(status, containing: "已解鎖")
        let card = app.descendants(matching: .any)["skin-card-sketch"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "The sketch card is shown")
        card.press(forDuration: 1.0)
        sleep(1)
        XCTAssertTrue(app.buttons["skin-badge-blackgold"].label.contains("使用中"), "Black-gold is still worn: \(app.buttons["skin-badge-blackgold"].label)")
        app.buttons["skin-badge-blackgold"].tap()
        waitForLabel(status, containing: "使用中")
        app.buttons["bar-lobby"].tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5), "Back in the lobby")
        sleep(2)
        let points = [CGVector(dx: 0.5, dy: 0.035), CGVector(dx: 0.5, dy: 0.15), CGVector(dx: 0.5, dy: 0.25)]
        let colours = points.map { pixel(app, $0) }
        let dark = colours.filter(isDark)
        XCTAssertGreaterThanOrEqual(dark.count, 2, "The lobby is still black-gold: \(colours.map { String(format: "%06X", $0) })")
    }
}
