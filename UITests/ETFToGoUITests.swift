import XCTest

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
        XCTAssertTrue(app.staticTexts["portfolio-value"].waitForExistence(timeout: 5)); capture(app,"screen-pocket")
        quickPick(app, "dividends")
        XCTAssertTrue(app.buttons["新增配息紀錄"].waitForExistence(timeout: 5)); capture(app,"screen-dividends")
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
        XCTAssertTrue(app.buttons["tool-combo"].waitForExistence(timeout: 5)); app.buttons["tool-combo"].tap()
        XCTAssertTrue(app.buttons["combo-settings"].waitForExistence(timeout: 5)); capture(app, "combo")
        reveal(app, app.buttons["combo-settings"])
        XCTAssertTrue(app.textFields["combo-monthly"].waitForExistence(timeout: 5)); capture(app, "combo-settings")
        // 開始試算 sits at the end of the page: it must scroll clear of the bottom bar and run.
        reveal(app, app.buttons["combo-run"])
        XCTAssertTrue(app.navigationBars["試算結果"].waitForExistence(timeout: 5)); capture(app, "combo-result")
    }
    func testDesignShowcase() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--open", "tools"]; app.launch()
        XCTAssertTrue(app.buttons["tool-design"].waitForExistence(timeout: 10)); app.buttons["tool-design"].tap()
        let record = app.buttons["showcase-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10)); sleep(2); capture(app, "design-home-blackgold")
        record.tap(); sleep(2); record.tap()
        sleep(3); capture(app, "design-home-after-record")
        XCTAssertTrue(app.staticTexts["showcase-amount"].label.contains("1,880"), "Two records add 2 × 320 once each: \(app.staticTexts["showcase-amount"].label)")
        XCTAssertTrue(record.isHittable, "Tapping twice does not leave the screen stuck")
        app.buttons["skin-picker"].tap(); sleep(2); capture(app, "design-home-stitch")
        app.buttons["skin-picker"].tap(); sleep(2); capture(app, "design-home-sketch")
        app.buttons["skin-picker"].tap()
        app.buttons["showcase-tab-fees"].tap()
        XCTAssertTrue(app.buttons["fee-row-1"].waitForExistence(timeout: 5)); app.buttons["fee-row-1"].tap(); sleep(2); capture(app, "design-fees")
    }
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
        XCTAssertTrue(app.buttons["home-add-favorite"].waitForExistence(timeout: 5))
        app.swipeUp(); capture(app, "home-lower")
        reveal(app, app.buttons["試算 10 年"]); capture(app, "home-combo-10y")
        reveal(app, app.buttons["home-combo"])
        XCTAssertTrue(app.buttons["combo-settings"].waitForExistence(timeout: 5), "The combined simulation opens from the pocket")
    }
    func testHoldingSurvivesRelaunch() {
        let app = launch(["--open", "pocket"])
        XCTAssertTrue(app.buttons["home-add-holding"].waitForExistence(timeout: 10))
        app.buttons["home-add-holding"].tap()
        app.textFields["holding-symbol"].tap(); app.textFields["holding-symbol"].typeText("0050")
        let name = app.textFields["holding-name"]
        if (name.value as? String) == "名稱（清單沒有時填寫）" { name.tap(); name.typeText("Test ETF") }
        app.textFields["holding-shares"].tap(); app.textFields["holding-shares"].typeText("1000")
        app.textFields["holding-cost"].tap(); app.textFields["holding-cost"].typeText("50")
        app.textFields["holding-broker"].tap(); app.textFields["holding-broker"].typeText("Test Broker")
        app.buttons["save-holding"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["save-holding"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["portfolio-value"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["portfolio-value"].label, "—", "The asset card shows the saved holding")
        app.terminate(); app.launchArguments = ["--ui-testing", "--open", "pocket"]; app.launch()
        XCTAssertTrue(app.buttons["home-holdings"].waitForExistence(timeout: 10)); reveal(app, app.buttons["home-holdings"])
        XCTAssertTrue(app.staticTexts["0050"].waitForExistence(timeout: 10))
        app.buttons["holdings-trades"].tap()
        XCTAssertTrue(app.staticTexts["買進"].waitForExistence(timeout: 5), "Saving a new holding is recorded in the trade log")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["holdings-allocation"].waitForExistence(timeout: 5))
        app.buttons["holdings-allocation"].tap()
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
            ("lobby-dividends", app.buttons["新增配息紀錄"], "配息"),
            ("lobby-pocket", app.staticTexts["portfolio-value"], "口袋"),
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
        for skin in ["blackgold", "stitch", "sketch"] {
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
        let app = launch(["--open", "find"])
        XCTAssertTrue(app.textFields["fund-search"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.count, 0)
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
}
