import XCTest

/// The two App Store pictures that need real data from the exchanges and the fund companies. Run only by the
/// `store-screens` step of native-ui.yml (the normal test step skips this class): from a CI runner those sites may be
/// slow or closed, so a test that gets no data saves what is on screen as `<name>-FAILED.png` and says why.
///
/// The pictures go to the folder named by `STORE_SCREENS_DIR` (passed by xcodebuild as `TEST_RUNNER_STORE_SCREENS_DIR`)
/// and are attached to the test as well.
final class StoreScreensUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    /// 回測: 0050 at 100%, 10,000 a month from 5 years ago. The first download of five years takes about four minutes
    /// (one request per month, two seconds apart); up to eight are allowed.
    func testStoreBacktest() {
        let app = launch("backtest")
        let run = app.buttons["backtest-run"]
        guard run.waitForExistence(timeout: 20) else { return fail(app, "store-backtest", "回測 did not open") }
        // `--reset` put the form back to how it first opens; said here so a changed default is noticed.
        XCTAssertEqual(app.textFields["backtest-weight-0050"].value as? String, "100", "0050 at 100%")
        XCTAssertEqual(app.textFields["backtest-monthly"].value as? String, "10000", "10,000 a month")
        let fiveYears = app.buttons["5 年前"]
        if fiveYears.exists, !fiveYears.isSelected { fiveYears.tap() }
        for _ in 0..<6 where !run.isHittable { app.swipeUp() }
        guard run.isHittable else { return fail(app, "store-backtest", "開始回測 could not be reached") }
        run.tap()

        let endValue = app.staticTexts["backtest-end-value"]
        let deadline = Date().addingTimeInterval(8 * 60)
        // While it downloads, 開始回測 is replaced by the progress card; it comes back when the run is over.
        sleep(2)
        while Date() < deadline, !endValue.exists, !run.exists { sleep(5) }
        guard endValue.exists else {
            return fail(app, "store-backtest", run.exists ? "the run ended without a result" : "no result after 8 minutes")
        }
        // The result card's figures and curve, from its first line down; then long enough for the scroll bar to fade.
        settle(app, endValue, at: 0.2)
        sleep(3)
        save(app, "store-backtest")
    }

    /// 持股透視 → 重疊成分 with the demo pocket: the holdings of the pocket's ETFs are fetched from the fund companies,
    /// and the pairs that share stocks are listed. Up to three minutes.
    func testStoreOverlap() {
        var app = launch("exposure")
        var tab = app.buttons["重疊成分"]
        guard tab.waitForExistence(timeout: 20) else { return fail(app, "store-overlap", "持股透視 did not open") }
        tab.tap()
        let fetch = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "取得 ", "成分股")).firstMatch
        guard fetch.waitForExistence(timeout: 10) else { return fail(app, "store-overlap", "no button fetches the holdings") }
        for _ in 0..<4 where !fetch.isHittable { app.swipeUp() }
        fetch.tap()

        let busy = app.buttons["取得中…"]
        let pairs = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " × "))
        let deadline = Date().addingTimeInterval(3 * 60)
        sleep(2)
        // Every ETF is asked in turn; the list is whole once the button is no longer busy.
        while Date() < deadline, busy.exists { sleep(3) }
        guard pairs.firstMatch.waitForExistence(timeout: 5) else {
            return fail(app, "store-overlap", busy.exists ? "still fetching after 3 minutes" : "no pair of ETFs came back with holdings")
        }
        // The pocket's bond ETF comes back with 「暫時取不到，稍後再試」 in red, which stays until the page is left. The
        // picture is the page as it opens the next time, with the holdings that did arrive kept on the phone.
        app.terminate()
        app = launch("exposure", reset: false)
        tab = app.buttons["重疊成分"]
        guard tab.waitForExistence(timeout: 20) else { return fail(app, "store-overlap", "持股透視 did not open again") }
        tab.tap()
        let kept = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " × ")).firstMatch
        guard kept.waitForExistence(timeout: 10) else { return fail(app, "store-overlap", "the fetched holdings were not kept") }
        sleep(1)
        save(app, "store-overlap")
    }

    // MARK: Helpers

    /// `reset` false keeps the records of the launch before (the seeds add nothing to a pocket that is already filled).
    private func launch(_ screen: String, reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (reset ? ["--reset"] : []) + ["--quiet-toasts", "--skip-onboarding", "--demo-store", "--open", screen]
        app.launch()
        return app
    }

    /// Scrolls until `element`'s top is about `fraction` of the way down the screen. Slow drags that are held at the
    /// end, so the list stops where the finger stops.
    private func settle(_ app: XCUIApplication, _ element: XCUIElement, at fraction: CGFloat) {
        let screen = app.windows.firstMatch.frame
        guard screen.height > 0 else { return }
        for _ in 0..<8 {
            let offset = element.frame.minY - screen.height * fraction
            if abs(offset) < 24 { return }
            // One drag moves the list by at most a third of the screen; it starts in the page's right margin, clear of
            // the form's fields and switches.
            let move = max(-screen.height / 3, min(screen.height / 3, offset))
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
            let to = from.withOffset(CGVector(dx: 0, dy: -move))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        }
    }

    /// The data did not arrive: what is on screen is kept under `<name>-FAILED`, and the test says why.
    private func fail(_ app: XCUIApplication, _ name: String, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
        save(app, name + "-FAILED")
        XCTFail("\(name): \(reason)", file: file, line: line)
    }

    /// The whole screen, status bar included, as `simctl io screenshot` takes it.
    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["STORE_SCREENS_DIR"], !folder.isEmpty else { return }
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do { try shot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png")) } catch {
            print("StoreScreens: \(name).png was not written to \(folder): \(error.localizedDescription)")
        }
    }
}
