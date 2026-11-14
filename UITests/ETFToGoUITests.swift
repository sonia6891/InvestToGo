import XCTest
import UIKit

final class ETFToGoUITests: XCTestCase {
    func testOTCCatalogAndRestoredResearchNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--skip-onboarding", "--open", "find"]; app.launch()
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
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--skip-onboarding"] + arguments; app.launch(); return app
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
        let app=XCUIApplication(); app.launchArguments=["--ui-testing","--reset","--skip-onboarding","--open","find"]; app.launch()
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
        app.terminate(); app.launchArguments = ["--ui-testing", "--skip-onboarding", "--open", "pocket"]; app.launch()
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
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--skip-onboarding", "--skin", id, "--open", "skinKit"]; app.launch()
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
        // 0050 is held: only a held code's dividend pays (re-review N1).
        let app = launch(["--demo-held"])
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

    // MARK: Splash, onboarding, achievements and level-up (spec 5.1, 5.2, 5.11, 5.12)

    /// A launch with the first-launch flow: a fresh install, no `--skip-onboarding`.
    private func launchFirstTime() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"]; app.launch(); return app
    }
    private func waitSelected(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed, "\(element) is selected", file: file, line: line)
    }
    private func onboardingNext(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "The page has 下一步", file: file, line: line)
        next.tap()
    }
    /// Splash → 定期定額 → 下一步 → 3,000 and 0050 → 下一步: on page 3.
    private func onboardToReminders(_ app: XCUIApplication, capturing: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let splash = app.buttons["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 10), "A first launch opens on the splash", file: file, line: line)
        if capturing {
            XCTAssertTrue(app.staticTexts["SKN×001"].exists, "The splash shows the worn skin's code", file: file, line: line)
            XCTAssertTrue(app.staticTexts["存 ETF，也存下好習慣。"].exists, file: file, line: line)
            XCTAssertFalse(app.buttons["lobby-find"].exists, "Not the lobby yet", file: file, line: line)
            sleep(1); capture(app, "splash")
        }
        splash.tap()
        let dca = app.buttons["habit-dca"]
        XCTAssertTrue(dca.waitForExistence(timeout: 5), "Page 1 asks for a habit", file: file, line: line)
        dca.tap()
        waitSelected(dca, file: file, line: line)
        if capturing { sleep(1); capture(app, "onboarding-1") }
        onboardingNext(app, file: file, line: line)
        let amount = app.buttons["amount-3000"], etf = app.buttons["etf-0050"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Page 2 asks for an amount", file: file, line: line)
        amount.tap(); etf.tap()
        waitSelected(amount, file: file, line: line); waitSelected(etf, file: file, line: line)
        if capturing { sleep(1); capture(app, "onboarding-2") }
        onboardingNext(app, file: file, line: line)
        XCTAssertTrue(app.buttons["day-6"].waitForExistence(timeout: 5), "Page 3 asks for the debit day", file: file, line: line)
    }

    func testFirstLaunchOnboarding() {
        let app = launchFirstTime()
        onboardToReminders(app, capturing: true)
        let day = app.buttons["day-6"]
        day.tap()
        waitSelected(day)
        sleep(1); capture(app, "onboarding-3")
        onboardingNext(app)
        // Page 4: one 「開始」 and where the data lives; no sign-in buttons until sign-in exists (ruling R32).
        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Page 4 offers 開始")
        XCTAssertEqual(start.label, "開始")
        XCTAssertTrue(app.buttons["login-later"].exists, "稍後再說 is still there, silent")
        for button in ["login-apple", "login-google", "login-email"] { XCTAssertFalse(app.buttons[button].exists, "\(button) is gone") }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '資料先存在這支 iPhone，登入功能即將開放'")).firstMatch.exists, "Says where the data lives")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '同意服務條款'")).firstMatch.exists, "No terms line")
        sleep(1); capture(app, "onboarding-4-start")
        start.tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5), "開始 goes to the lobby")
        XCTAssertFalse(app.buttons["splash"].exists)
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 10), "The next launch goes straight to the lobby")
        XCTAssertFalse(app.buttons["splash"].exists, "No splash once onboarded")
        XCTAssertFalse(app.buttons["habit-dca"].exists, "No onboarding once onboarded")
    }

    /// 工具 › 提醒 has the debit-day reminder chosen in onboarding: on or off, the day and the time (final review I5).
    func testReminderCenterHasTheDebitDayReminder() {
        let app = launch(["--open", "reminders"])
        let toggle = app.switches["reminder-dca-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "提醒 lists 定期定額扣款日提醒")
        XCTAssertTrue(app.descendants(matching: .any)["reminder-dca-day"].exists, "with its day")
        XCTAssertTrue(app.descendants(matching: .any)["reminder-dca-time"].exists, "and its time")
        sleep(1); capture(app, "reminders-dca")
    }

    func testBackInOnboarding() {
        let app = launchFirstTime()
        onboardToReminders(app)
        let back = app.buttons["onboarding-back"]
        XCTAssertTrue(back.exists, "Page 3 can go back")
        back.tap()
        let amount = app.buttons["amount-3000"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "返回 goes back to page 2")
        XCTAssertFalse(app.buttons["day-6"].exists, "Page 3 is gone")
        waitSelected(amount)
        waitSelected(app.buttons["etf-0050"])
    }

    func testAchievementWall() {
        let app = launch(["--demo-streak", "12", "--open", "achievements"])
        let punch = app.descendants(matching: .any)["achievement-dcaPunchCard"]
        XCTAssertTrue(punch.waitForExistence(timeout: 10), "定期定額打卡 is on the wall")
        waitForLabel(app.staticTexts["bar-title"], "成就")
        let unlocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH '已解鎖 '"), object: punch)
        XCTAssertEqual(XCTWaiter().wait(for: [unlocked], timeout: 5), .completed, "Twelve months unlock 定期定額打卡: \(String(describing: punch.value))")
        let value = punch.value as? String ?? ""
        XCTAssertNotNil(value.range(of: "[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}", options: .regularExpression), "With its date: \(value)")
        let locked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'achievement-' AND value MATCHES %@", "^[0-9]+ / [0-9]+$"))
        XCTAssertGreaterThan(locked.count, 0, "A locked achievement shows its progress as numbers")
        // No feature counts 體檢完成 yet: 「即將推出」, not 0 / 1 forever (ruling R31).
        let soon = app.descendants(matching: .any)["achievement-checkupDone"]
        if !soon.exists { app.swipeUp() }
        XCTAssertTrue(soon.waitForExistence(timeout: 5))
        XCTAssertEqual(soon.value as? String, "即將推出")
        sleep(1); capture(app, "achievements")
    }

    func testLevelUpShowsOnce() {
        let app = launch(["--demo-xp", "290", "--demo-held"])
        let xp = app.descendants(matching: .any)["lobby-xp"]
        XCTAssertTrue(xp.waitForExistence(timeout: 10))
        XCTAssertEqual(xp.value as? String, "290 經驗")
        let level = app.staticTexts["levelup-level"]
        XCTAssertFalse(level.exists, "No celebration at launch")
        app.buttons["lobby-dividends"].tap()
        let log = app.buttons["dividends-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5)); log.tap()
        let symbol = app.textFields["dividend-symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5), "「記一筆配息」 opens the dividend form")
        symbol.tap(); symbol.typeText("0050")
        app.textFields["dividend-shares"].tap(); app.textFields["dividend-shares"].typeText("1000")
        app.textFields["dividend-per-share"].tap(); app.textFields["dividend-per-share"].typeText("1")
        app.buttons["save-dividend"].tap()
        // The +20 toast comes first, then the celebration over it.
        XCTAssertTrue(app.staticTexts["dividend-xp-toast"].waitForExistence(timeout: 5), "The +20 toast is not lost")
        XCTAssertTrue(level.waitForExistence(timeout: 10), "Crossing 300 experience celebrates level 2")
        XCTAssertEqual(level.label, "LV.2")
        XCTAssertTrue(app.staticTexts["LEVEL×UP"].exists)
        XCTAssertTrue(app.buttons["levelup-share"].exists, "分享這一刻")
        sleep(1); capture(app, "level-up")
        app.buttons["levelup-accept"].tap()
        XCTAssertTrue(level.waitForNonExistence(timeout: 5), "收下 closes it")
        app.buttons["bar-lobby"].tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5))
        XCTAssertEqual(xp.value as? String, "310 經驗")
        app.buttons["lobby-dividends"].tap()
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        app.buttons["bar-lobby"].tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5))
        XCTAssertFalse(level.waitForExistence(timeout: 4), "Shown once: not again after going in and out")
        app.terminate(); app.launchArguments = ["--ui-testing", "--skip-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 10))
        XCTAssertFalse(level.waitForExistence(timeout: 4), "Shown once: not again after a relaunch")
    }

    // MARK: Feel, states and accessibility (spec 3.5, 7.1, 9; Task 12)

    /// 大廳 → 配息 → 記一筆 (saved). The form closes onto 配息.
    private func logDividendFromLobby(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["lobby-dividends"].waitForExistence(timeout: 10), "The lobby opens", file: file, line: line)
        app.buttons["lobby-dividends"].tap()
        let log = app.buttons["dividends-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "配息 opens", file: file, line: line); log.tap()
        let symbol = app.textFields["dividend-symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5), "「記一筆配息」 opens the dividend form", file: file, line: line)
        symbol.tap(); symbol.typeText("0050")
        app.textFields["dividend-shares"].tap(); app.textFields["dividend-shares"].typeText("1000")
        app.textFields["dividend-per-share"].tap(); app.textFields["dividend-per-share"].typeText("1")
        app.buttons["save-dividend"].tap()
    }

    /// With `--reduce-motion` the whole loop still works and no burst of shards is ever drawn. The same loop without
    /// it shows the burst first, so the check below can see one when it is there.
    func testReduceMotionStillWorks() {
        let burst = { (app: XCUIApplication) in app.descendants(matching: .any)["burst"] }
        let moving = launch(["--demo-held"])
        logDividendFromLobby(moving)
        XCTAssertTrue(burst(moving).waitForExistence(timeout: 5), "Without Reduce Motion the coin lands with a burst")
        moving.terminate()

        let app = launch(["--reduce-motion", "--demo-held"])
        logDividendFromLobby(app)
        let toast = app.staticTexts["dividend-xp-toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "The reward still shows with Reduce Motion")
        XCTAssertFalse(burst(app).waitForExistence(timeout: 3), "Reduce Motion: no shards")
        capture(app, "reduce-motion-dividend")
        app.buttons["bar-lobby"].tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5), "Back in the lobby")
        XCTAssertFalse(burst(app).exists, "Reduce Motion: no shards in the lobby either")
    }

    /// Scrolls until the element is on screen and can be tapped, without tapping it.
    private func assertReachable(_ app: XCUIApplication, _ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(name) exists", file: file, line: line)
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(name) can be tapped at the largest text size", file: file, line: line)
    }

    /// At the largest accessibility text size the main buttons of 大廳 → 找 ETF → 詳情 can all be tapped.
    func testLargestTextMainFlow() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let find = app.buttons["lobby-find"]
        XCTAssertTrue(find.waitForExistence(timeout: 10), "The lobby opens")
        sleep(1); capture(app, "largest-text-lobby")
        for entry in ["lobby-find", "lobby-dividends", "lobby-pocket", "lobby-tools"] { XCTAssertTrue(app.buttons[entry].isHittable, "\(entry) can be tapped") }
        find.tap()
        let search = app.textFields["fund-search"]
        assertReachable(app, search, "The search field")
        XCTAssertTrue(app.buttons["bar-lobby"].isHittable, "‹ 大廳 can be tapped")
        XCTAssertTrue(app.buttons["bar-quick"].isHittable, "The quick pick can be tapped")
        sleep(1); capture(app, "largest-text-find")
        search.tap(); search.typeText("0050\n")
        let row = app.staticTexts["元大台灣50"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "0050 is listed")
        XCTAssertTrue(row.isHittable, "The row can be tapped"); row.tap()
        assertReachable(app, app.buttons["圖鑑卡"], "圖鑑卡")
        sleep(1); capture(app, "largest-text-detail")
        assertReachable(app, app.buttons["走勢"], "走勢")
        assertReachable(app, app.buttons["資訊"], "資訊")
        XCTAssertTrue(app.buttons["bar-lobby"].isHittable, "‹ 大廳 can be tapped on the detail")
    }

    /// Whether any pixel of the screenshot is within ±6 of the colour on every channel.
    private func screenshotContains(_ shot: XCUIScreenshot, _ colour: UInt32) -> Bool {
        guard let image = shot.image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard drawn else { return false }
        let r = Int((colour >> 16) & 0xFF), g = Int((colour >> 8) & 0xFF), b = Int(colour & 0xFF)
        var i = 0
        while i < bytes.count {
            if abs(Int(bytes[i]) - r) <= 6, abs(Int(bytes[i + 1]) - g) <= 6, abs(Int(bytes[i + 2]) - b) <= 6 { return true }
            i += 4
        }
        return false
    }

    /// Black-gold → 手繪 in the carousel, then every main screen: on sketch paper, with no black-gold gold left anywhere.
    func testSkinSwitchLeavesNoOldColor() {
        let app = launch(["--skin", "blackgold", "--demo-level", "7", "--demo-streak", "12", "--open", "tools"])
        openSkins(app)
        app.buttons["skin-badge-sketch"].tap()
        waitForLabel(app.buttons["skin-apply"], "換上這套")
        app.buttons["skin-apply"].tap()
        XCTAssertTrue(app.buttons["lobby-find"].waitForExistence(timeout: 5), "換上這套 goes back to the lobby")
        let screens: [(String, XCUIElement)] = [
            ("lobby", app.buttons["lobby-find"]),
            ("find", app.textFields["fund-search"]),
            ("pocket", app.buttons["pocket-add"]),
            ("dividends", app.buttons["dividends-log"]),
            ("tools", app.buttons["tool-backup"]),
        ]
        for (name, marker) in screens {
            if name == "find" { app.buttons["lobby-find"].tap() } else if name != "lobby" { quickPick(app, name) }
            XCTAssertTrue(marker.waitForExistence(timeout: 5), "\(name) opens")
            sleep(2)
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot: shot); attachment.name = "after-switch-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            let points = [CGVector(dx: 0.015, dy: 0.3), CGVector(dx: 0.015, dy: 0.5), CGVector(dx: 0.015, dy: 0.7)]
            let colours = points.map { pixel(app, $0) }
            XCTAssertGreaterThanOrEqual(colours.filter { sameColour($0, 0xFAF8F3) }.count, 2,
                                        "\(name) is on sketch paper: \(colours.map { String(format: "%06X", $0) })")
            XCTAssertFalse(screenshotContains(shot, 0xF2B632), "\(name) has no black-gold gold left")
        }
    }

    /// `--offline`: the thin bar at the top, and 找 ETF still lists the last data with 「再試一次」.
    func testOfflineBar() {
        let app = launch(["--offline", "--open", "find"])
        let bar = app.staticTexts["offline-bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "The offline bar shows")
        XCTAssertTrue(bar.label.hasPrefix("離線中"), "It says 離線中: \(bar.label)")
        XCTAssertTrue(app.buttons["再試一次"].waitForExistence(timeout: 5), "找 ETF offers 「再試一次」")
        XCTAssertTrue(app.descendants(matching: .any)["load-failed-last"].exists, "The time of the last good data is shown")
        XCTAssertTrue(app.staticTexts["0050"].waitForExistence(timeout: 5), "The list still shows the last data")
        sleep(1); capture(app, "offline-find")
    }

    /// 重疊成分 is a member feature: a non-member sees the lock, a member (--demo-member) does not.
    func testNonMemberSeesOverlapLock() {
        let app = launch(["--open", "exposure"])
        let tab = app.buttons["重疊成分"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "持股透視 opens")
        tab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["member-lock-overlap"].waitForExistence(timeout: 5), "A non-member sees the overlap lock")
        app.terminate()
        let member = launch(["--demo-member", "--open", "exposure"])
        XCTAssertTrue(member.buttons["重疊成分"].waitForExistence(timeout: 10))
        member.buttons["重疊成分"].tap()
        XCTAssertTrue(member.staticTexts["至少需要兩檔持有 ETF 的成分資料才能比較重疊。"].waitForExistence(timeout: 5), "A member sees the overlap list")
        XCTAssertFalse(member.descendants(matching: .any)["member-lock-overlap"].exists, "A member sees no lock")
    }
    /// 存錢目標反推 is a member feature: a non-member sees the lock, a member sees the monthly amount.
    func testGoalPlannerLockAndMember() {
        let app = launch(["--open", "goalPlanner"])
        XCTAssertTrue(app.descendants(matching: .any)["member-lock-goalPlanner"].waitForExistence(timeout: 10), "A non-member sees the lock")
        app.terminate()
        let member = launch(["--demo-member", "--open", "goalPlanner"])
        XCTAssertTrue(member.staticTexts["goal-planner-monthly"].waitForExistence(timeout: 10), "A member sees 每月需投入")
        XCTAssertFalse(member.descendants(matching: .any)["member-lock-goalPlanner"].exists)
    }
    /// 回測 is a member feature: a non-member sees the lock, a member sees the form. Nothing is downloaded here.
    func testBacktestLockAndMember() {
        let app = launch(["--open", "backtest"])
        XCTAssertTrue(app.descendants(matching: .any)["member-lock-backtest"].waitForExistence(timeout: 10), "A non-member sees the lock")
        app.terminate()
        let member = launch(["--demo-member", "--open", "backtest"])
        XCTAssertTrue(member.buttons["backtest-run"].waitForExistence(timeout: 10), "A member sees the form and 開始回測")
        XCTAssertTrue(member.textFields["backtest-monthly"].exists, "The form has 每月投入")
        XCTAssertFalse(member.descendants(matching: .any)["member-lock-backtest"].exists)
    }
    /// 主動式追蹤 is a member feature: a non-member sees the lock; a member sees what changed between the two newest days
    /// of a favourite active ETF. The holdings are seeded (`--demo-active`): nothing is downloaded here.
    func testActiveTrackingLockAndMember() {
        let dates = "11/13 與 11/11 相比"
        let app = launch(["--demo-active", "--open", "activeTracking"])
        XCTAssertTrue(app.descendants(matching: .any)["member-lock-activeTracking"].waitForExistence(timeout: 10), "A non-member sees the lock")
        XCTAssertFalse(app.buttons["active-tracking-refresh"].exists, "The list is not there for a non-member")
        app.terminate()
        let member = launch(["--demo-member", "--demo-active", "--open", "activeTracking"])
        XCTAssertTrue(member.buttons["active-tracking-refresh"].waitForExistence(timeout: 10), "A member sees the list and 更新")
        XCTAssertTrue(member.staticTexts[dates].exists, "The two days compared are said plainly")
        XCTAssertTrue(member.staticTexts["資料來自各投信官網公開的持股，更新時間依投信而定。"].exists)
        XCTAssertFalse(member.descendants(matching: .any)["member-lock-activeTracking"].exists)
        sleep(1); capture(member, "active-tracking-member")
        member.terminate()
        // The fund's own 持股 tab: the holdings are free, 持股變化 is the member's.
        let detail = launch(["--demo-active", "--quiet-toasts", "--open", "detail", "--symbol", "00982A"])
        XCTAssertTrue(detail.buttons["持股"].waitForExistence(timeout: 10))
        detail.buttons["持股"].tap()
        XCTAssertTrue(detail.buttons["holding-changes-lock"].waitForExistence(timeout: 5), "A non-member sees one line that opens 會員")
        XCTAssertTrue(detail.buttons["更新成分股"].exists, "The holdings themselves stay free")
        XCTAssertFalse(detail.staticTexts[dates].exists, "The change is not shown to a non-member")
        detail.terminate()
        let memberDetail = launch(["--demo-member", "--demo-active", "--quiet-toasts", "--open", "detail", "--symbol", "00982A"])
        XCTAssertTrue(memberDetail.buttons["持股"].waitForExistence(timeout: 10))
        memberDetail.buttons["持股"].tap()
        XCTAssertTrue(memberDetail.staticTexts[dates].waitForExistence(timeout: 5), "A member sees the change on the fund's own page")
        XCTAssertFalse(memberDetail.buttons["holding-changes-lock"].exists)
    }
}
