import XCTest

final class ETFToGoUITests: XCTestCase {
    func testOTCCatalogAndRestoredResearchNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--tab", "1"]; app.launch()
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("00679B\n")
        let fund = app.staticTexts["元大美債20年"]; XCTAssertTrue(fund.waitForExistence(timeout: 5)); fund.tap()
        XCTAssertTrue(app.buttons["持股"].waitForExistence(timeout: 5))
        app.buttons["持股"].tap()
        XCTAssertTrue(app.buttons["更新成分股"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["尚無成分資料"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "restored-components"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["tab-工具"].tap()
        XCTAssertTrue(app.buttons["tool-broker"].waitForExistence(timeout: 5))
        app.buttons["tool-broker"].tap()
        XCTAssertTrue(app.textFields["broker-import-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["選擇庫存 CSV"].exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testAnnualFeesAndHistoryNavigation() {
        let app=XCUIApplication(); app.launchArguments=["--ui-testing","--reset","--tab","1"]; app.launch()
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
    func testAllTabsAndSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"]; app.launch()
        XCTAssertTrue(app.staticTexts["portfolio-value"].waitForExistence(timeout: 10)); capture(app,"screen-0")
        app.buttons["tab-探索"].tap(); capture(app,"screen-1")
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("0050\n")
        XCTAssertTrue(app.staticTexts["元大台灣50"].exists)
        XCTAssertFalse(app.staticTexts["國泰永續高股息"].exists)
        app.buttons["tab-持有"].tap()
        XCTAssertTrue(app.buttons["add-holding"].waitForExistence(timeout: 5)); capture(app,"screen-2")
        app.buttons["tab-配息"].tap()
        XCTAssertTrue(app.buttons["新增配息紀錄"].waitForExistence(timeout: 5)); capture(app,"screen-3")
        app.buttons["tab-工具"].tap(); capture(app,"screen-4")
        XCTAssertTrue(app.buttons["tool-backup"].waitForExistence(timeout: 5))
    }
    func testStockDetailAndComboSimulation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset", "--tab", "1"]; app.launch()
        XCTAssertTrue(app.buttons["個股"].waitForExistence(timeout: 10))
        app.buttons["個股"].tap()
        let search = app.textFields["fund-search"]; XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("2317\n")
        let row = app.staticTexts["鴻海"].firstMatch; XCTAssertTrue(row.waitForExistence(timeout: 5)); capture(app, "stock-search")
        row.tap()
        XCTAssertTrue(app.buttons["stock-add-combo"].waitForExistence(timeout: 5)); capture(app, "stock-detail")
        app.buttons["財務"].tap(); capture(app, "stock-finance")
        app.buttons["股利"].tap(); capture(app, "stock-dividends")
        app.buttons["stock-add-combo"].tap()
        XCTAssertTrue(app.buttons["combo-settings"].waitForExistence(timeout: 5)); capture(app, "combo")
        app.buttons["combo-settings"].tap()
        XCTAssertTrue(app.buttons["combo-run"].waitForExistence(timeout: 5)); capture(app, "combo-settings")
        app.buttons["combo-run"].tap()
        XCTAssertTrue(app.navigationBars["試算結果"].waitForExistence(timeout: 5)); capture(app, "combo-result")
    }
    func testHomeSearchWatchlistAndCombo() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"]; app.launch()
        XCTAssertTrue(app.buttons["home-search"].waitForExistence(timeout: 10)); capture(app, "home-empty")
        app.buttons["home-search"].tap()
        let search = app.textFields["fund-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "The home search opens 探索")
        let done = app.buttons["完成搜尋"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The home search focuses the field")
        done.tap()
        app.buttons["tab-首頁"].tap()
        XCTAssertTrue(app.buttons["home-add-favorite"].waitForExistence(timeout: 5))
        app.swipeUp(); capture(app, "home-lower")
        app.buttons["試算 10 年"].tap(); capture(app, "home-combo-10y")
        app.buttons["home-combo"].tap()
        XCTAssertTrue(app.buttons["combo-settings"].waitForExistence(timeout: 5), "The combined simulation opens from the home page")
    }
    func testHoldingSurvivesRelaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset"]; app.launch()
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
        app.terminate(); app.launchArguments = ["--ui-testing", "--tab", "2"]; app.launch()
        XCTAssertTrue(app.staticTexts["0050"].waitForExistence(timeout: 10))
        app.buttons["holdings-trades"].tap()
        XCTAssertTrue(app.staticTexts["買進"].waitForExistence(timeout: 5), "Saving a new holding is recorded in the trade log")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["holdings-allocation"].waitForExistence(timeout: 5))
        app.buttons["holdings-allocation"].tap()
        XCTAssertTrue(app.staticTexts["券商帳戶"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Broker"].exists)
    }
}
