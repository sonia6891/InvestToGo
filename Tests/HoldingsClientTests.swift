import XCTest
@testable import ETFToGo

/// Answers like the fund companies do, from a closure, and keeps what was asked.
private actor FakeHoldingsTransport: HoldingsTransport {
    struct Call: Sendable { let method: String; let url: String; let body: Data? }
    typealias Answer = @Sendable (Call) throws -> Data

    private(set) var calls: [Call] = []
    private var answer: Answer

    init(_ answer: @escaping Answer) { self.answer = answer }

    func setAnswer(_ next: @escaping Answer) { answer = next }
    func urls(_ part: String = "") -> [String] { calls.map(\.url).filter { part.isEmpty || $0.contains(part) } }

    func get(_ url: URL) async throws -> Data { try take(Call(method: "GET", url: url.absoluteString, body: nil)) }
    func post(_ url: URL, json: Data?) async throws -> Data { try take(Call(method: "POST", url: url.absoluteString, body: json)) }

    private func take(_ call: Call) throws -> Data {
        calls.append(call)
        return try answer(call)
    }
}

private final class HoldingsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(days: Double) { lock.lock(); value = value.addingTimeInterval(days * 86_400); lock.unlock() }
}

/// Which fund companies' failures were reported, and as what.
private actor Reported {
    private(set) var issuers: [Issuer] = []
    private(set) var failures: [HoldingsFailure] = []
    /// Reports that were not a `HoldingsFailure` (there should be none).
    private(set) var others = 0
    func add(_ issuer: Issuer, _ error: Error) {
        issuers.append(issuer)
        if let failure = error as? HoldingsFailure { failures.append(failure) } else { others += 1 }
    }
}

final class HoldingsClientTests: XCTestCase {
    private var directory: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private let reported = Reported()

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("holdings-\(UUID().uuidString)", isDirectory: true)
        suite = "holdings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    /// Noon in Taipei on Saturday 2026-11-14: the day before is the latest trading day.
    private func saturday() -> HoldingsClock {
        HoldingsClock(GameRules.taipei.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!)
    }

    /// `offline`: what the app's own 離線中 says; the tests never read the simulator's real network.
    private func client(_ transport: FakeHoldingsTransport, _ clock: HoldingsClock, key: Bool = false, offline: Bool = false) -> HoldingsClient {
        let reported = self.reported
        return HoldingsClient(transport: transport, root: directory.appendingPathComponent("kept", isDirectory: true), defaults: defaults,
                              minInterval: 0, clock: { clock.now }, fugleKeySaved: { key },
                              fugle: { symbol in
                                  ComponentSnapshot(symbol: symbol, date: "2026-11-12", components: [FundComponent(symbol: "2330", name: "台積電", weight: 30)], source: "富果／投信揭露資料")
                              },
                              report: { error, issuer in await reported.add(issuer, error) },
                              deviceOffline: { offline })
    }

    private func snapshot(_ symbol: String, _ date: String, weight: Double = 50) -> ComponentSnapshot {
        ComponentSnapshot(symbol: symbol, date: date, components: [FundComponent(symbol: "2330", name: "台積電", weight: weight)], source: "test")
    }

    private static func yuanta(_ symbol: String, day: String = "20261113") -> Data {
        let rows = #"[{"code":"2330","name":"台積電","weights":58.7},{"code":"2317","name":"鴻海","weights":4.5}]"#
        return Data(("{\"PCF\":{\"markcd\":\"" + symbol + "\",\"trandate\":\"" + day + "\"},\"FundWeights\":{\"StockWeights\":" + rows + "}}").utf8)
    }

    private func object(_ data: Data?) -> [String: Any] {
        guard let data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }

    /// For `do { try await …; XCTFail("…") } catch { expect(error, "…") }`.
    private func expect(_ error: Error, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(error.localizedDescription, text, file: file, line: line)
    }

    // MARK: The brief's four

    @MainActor func testFailedFetchKeepsPreviousSnapshot() async throws {
        let url = directory.appendingPathComponent("p.json")
        let store = PortfolioStore(url: url)
        try store.saveComponents(snapshot("0050", "2026-11-10"))
        let transport = FakeHoldingsTransport { _ in throw URLError(.badServerResponse) }
        let clock = saturday()
        let subject = client(transport, clock)
        do { try await store.refreshComponents("0050", client: subject); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        XCTAssertEqual(store.data.components?["0050"]?.date, "2026-11-10")
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), ["2026-11-10"])
        let asked = await transport.urls()
        XCTAssertEqual(asked.count, 1, "0050 is 元大's (the name in the ETF list), so 元大 was asked")
        let issuers = await reported.issuers
        XCTAssertEqual(issuers, [.yuanta], "The failure is reported under the fund company alone")
        // A body that is not the company's JSON is the same failure (asked again once the half-hour pause is over).
        clock.advance(days: 31.0 / 1440)
        await transport.setAnswer { _ in Data("<html>維護中</html>".utf8) }
        do { try await store.refreshComponents("0050", client: subject); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let failures = await reported.failures
        XCTAssertEqual(failures, [HoldingsFailure(issuer: .yuanta, kind: .network, code: URLError.Code.badServerResponse.rawValue),
                                  HoldingsFailure(issuer: .yuanta, kind: .parse)])
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.data.components?["0050"]?.date, "2026-11-10")
        XCTAssertEqual(reopened.componentHistory(for: "0050").map(\.date), ["2026-11-10"])
    }

    @MainActor func testHistoryKeepsTwelveNewest() throws {
        let url = directory.appendingPathComponent("p.json")
        let store = PortfolioStore(url: url)
        XCTAssertTrue(store.componentHistory(for: "0050").isEmpty)
        // Saved out of order: the history is by the holdings' date, not by when they were saved.
        for day in [5, 14, 1, 9, 2, 13, 3, 12, 4, 11, 6, 10, 7, 8] {
            try store.saveComponents(snapshot("0050", String(format: "2026-09-%02d", day)))
        }
        try store.saveComponents(snapshot("00878", "2026-09-30"))
        let expected = (3...14).reversed().map { String(format: "2026-09-%02d", $0) }
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), expected, "12 kept, newest first")
        XCTAssertEqual(store.componentHistory(for: "00878").map(\.date), ["2026-09-30"])
        XCTAssertEqual(store.data.components?["0050"]?.date, "2026-09-08", "The current holdings are the ones saved last")
        // The same date again replaces that day's entry.
        try store.saveComponents(snapshot("0050", "2026-09-14", weight: 61))
        let history = store.componentHistory(for: "0050")
        XCTAssertEqual(history.map(\.date), expected)
        XCTAssertEqual(history.first?.components.first?.weight, 61)
        // A date older than the twelve kept does not push a newer one out.
        try store.saveComponents(snapshot("0050", "2026-08-01"))
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), expected)
        // Saved with the records, and in a backup.
        XCTAssertEqual(PortfolioStore(url: url).componentHistory(for: "0050").map(\.date), expected)
        let other = PortfolioStore(url: directory.appendingPathComponent("other.json"))
        try other.saveComponents(snapshot("0050", "2026-10-01"))
        try other.importBackup(Data(contentsOf: store.export()))
        XCTAssertEqual(other.componentHistory(for: "0050").map(\.date), ["2026-10-01"] + expected.dropLast())
    }

    /// A records file written before the history existed still opens, with no history.
    @MainActor func testRecordsWithoutHistoryStillOpen() throws {
        let url = directory.appendingPathComponent("old.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = #"{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{},"components":{"0050":{"symbol":"0050","date":"2026-10-01","components":[{"symbol":"2330","name":"台積電","weight":50}]}}}"#
        try Data(old.utf8).write(to: url)
        let store = PortfolioStore(url: url)
        XCTAssertNil(store.message)
        XCTAssertEqual(store.data.components?["0050"]?.date, "2026-10-01")
        XCTAssertNil(store.data.componentHistory)
        XCTAssertTrue(store.componentHistory(for: "0050").isEmpty)
        try store.saveComponents(snapshot("0050", "2026-10-02"))
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), ["2026-10-02"])
    }

    func testOneFetchPerDay() async throws {
        let transport = FakeHoldingsTransport { _ in HoldingsClientTests.yuanta("0050") }
        let clock = saturday()
        let subject = client(transport, clock)
        let first = try await subject.components(symbol: "0050", fundName: "元大台灣50")
        let second = try await subject.components(symbol: "0050", fundName: "元大台灣50")
        XCTAssertEqual(first.date, "2026-11-13")
        XCTAssertEqual(first.source, "元大投信")
        XCTAssertEqual(second.components.map(\.symbol), ["2330", "2317"])
        var asked = await transport.urls()
        XCTAssertEqual(asked, ["https://etfapi.yuantaetfs.com/ectranslation/api/bridge?APIType=ETFAPI&FuncId=PCF/Daily&ticker=0050"])
        // Today's copy is on disk: a new client (the app opened again) does not ask either.
        _ = try await client(transport, clock).components(symbol: "0050", fundName: "元大台灣50")
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 1)
        // Another ETF is its own download.
        await transport.setAnswer { _ in HoldingsClientTests.yuanta("0056") }
        _ = try await subject.components(symbol: "0056", fundName: "元大高股息")
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 2)
        // The next Taipei day asks again.
        clock.advance(days: 1)
        await transport.setAnswer { _ in HoldingsClientTests.yuanta("0050") }
        _ = try await subject.components(symbol: "0050", fundName: "元大台灣50")
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 3)
    }

    func testUnknownIssuerWithoutKey() async throws {
        let transport = FakeHoldingsTransport { _ in Data() }
        let clock = saturday()
        do { _ = try await client(transport, clock).components(symbol: "00939", fundName: "統一台灣高息動能"); XCTFail("Expected an error") } catch { expect(error, "這家投信暫不支援") }
        var asked = await transport.urls()
        XCTAssertTrue(asked.isEmpty, "Nobody is asked about a fund from another company")
        // With a 富果 key saved, 富果 answers for the companies the app does not read itself.
        let viaFugle = try await client(transport, clock, key: true).components(symbol: "00939", fundName: "統一台灣高息動能")
        XCTAssertEqual(viaFugle.source, "富果／投信揭露資料")
        asked = await transport.urls()
        XCTAssertTrue(asked.isEmpty)
        let issuers = await reported.issuers
        XCTAssertTrue(issuers.isEmpty)
    }

    // MARK: Fallback and reporting

    func testCompanyFailureFallsBackToFugleWhenAKeyIsSaved() async throws {
        let transport = FakeHoldingsTransport { _ in Data("<html>維護中</html>".utf8) }
        let value = try await client(transport, saturday(), key: true).components(symbol: "0050", fundName: "元大台灣50")
        XCTAssertEqual(value.source, "富果／投信揭露資料")
        let issuers = await reported.issuers
        XCTAssertEqual(issuers, [.yuanta], "元大's failure is still reported")
    }

    /// A code the catalogue would never hold is refused before any request.
    func testOddCodeAsksNobody() async {
        let transport = FakeHoldingsTransport { _ in HoldingsClientTests.yuanta("0050") }
        do { _ = try await client(transport, saturday()).components(symbol: "0050&x=1", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "ETF 代號格式不符。") }
        let asked = await transport.urls()
        XCTAssertTrue(asked.isEmpty)
    }

    // MARK: Each company's requests

    func testCathayChainAndThirtyDayLookup() async throws {
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("GetETFList") { return Data(#"{"totalCount":1,"result":[{"fundCode":"CN","stockCode":"00878"}],"returnCode":"2000","success":true}"#.utf8) }
            if call.url.contains("GetETFAssets") { return Data(#"{"result":{"preDate":"2026/11/13"},"returnCode":"2000","success":true}"#.utf8) }
            return Data(#"{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"}],"returnCode":"2000","success":true}"#.utf8)
        }
        let clock = saturday()
        let subject = client(transport, clock)
        let value = try await subject.components(symbol: "00878", fundName: "國泰永續高股息")
        XCTAssertEqual(value.date, "2026-11-13")
        XCTAssertEqual(value.components.first?.weight ?? 0, 11.26, accuracy: 1e-9)
        var asked = await transport.urls()
        XCTAssertEqual(asked, ["https://cwapi.cathaysite.com.tw/api/ETF/GetETFList?Keyword=00878",
                               "https://cwapi.cathaysite.com.tw/api/ETF/GetETFAssets?FundCode=CN",
                               "https://cwapi.cathaysite.com.tw/api/ETF/GetETFDetailStockList?FundCode=CN&SearchDate=2026-11-13"])
        let methods = await transport.calls.map(\.method)
        XCTAssertEqual(methods, ["GET", "GET", "GET"])
        // The fund code is kept for 30 days: the next day asks for the date and the holdings only.
        clock.advance(days: 1)
        _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息")
        asked = await transport.urls("GetETFList")
        XCTAssertEqual(asked.count, 1)
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 5)
        clock.advance(days: 30)
        _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息")
        asked = await transport.urls("GetETFList")
        XCTAssertEqual(asked.count, 2, "After 30 days the fund code is asked for again")
    }

    func testCtbcEncodesTheTokenAndStepsBackADay() async throws {
        let token = "aB+/c9=="
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("home/AuthToken") { return Data(#"{"ResultCode":0,"Data":{"token":"aB+/c9=="}}"#.utf8) }
            if call.url.contains("etf/ETFList") { return Data(#"{"ResultCode":0,"Data":{"Data":[{"ETF_ID":"00934","FID":"E0024"},{"ETF_ID":"00882","FID":"E0014"}]}}"#.utf8) }
            let body = (try? JSONSerialization.jsonObject(with: call.body ?? Data()) as? [String: Any]) ?? [:]
            // Nothing on Saturday: empty lists, as the site answers for a day it has no data for.
            guard body["StartDate"] as? String == "2026/11/13" else {
                return Data(#"{"ResultCode":0,"ResultMsg":"","Data":{"Fund":[],"FundAssets":[],"FundAssetsDetail":[]}}"#.utf8)
            }
            return Data(#"{"ResultCode":0,"Data":{"Fund":[{"ETF_ID":"00934","FID":"E0024"}],"FundAssets":[{"資料日期":"2026/11/13"}],"FundAssetsDetail":[{"Code":"STOCK","Data":[{"code_":"3293","name_":"鈊象電子","weights_":"8.10"}]}]}}"#.utf8)
        }
        let value = try await client(transport, saturday()).components(symbol: "00934", fundName: "中信成長高股息")
        XCTAssertEqual(value.date, "2026-11-13")
        XCTAssertEqual(value.source, "中國信託投信")
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.method), ["POST", "POST", "POST", "POST"])
        XCTAssertEqual(calls.map(\.url), [
            "https://www.ctbcinvestments.com.tw/API/home/AuthToken?token=www.ctbcinvestments.com",
            "https://www.ctbcinvestments.com.tw/API/etf/ETFList?token=aB%2B%2Fc9%3D%3D",
            "https://www.ctbcinvestments.com.tw/API/etf/ETFHoldingWeight?token=aB%2B%2Fc9%3D%3D",
            "https://www.ctbcinvestments.com.tw/API/etf/ETFHoldingWeight?token=aB%2B%2Fc9%3D%3D"])
        XCTAssertEqual(object(calls[0].body)["token"] as? String, "www.ctbcinvestments.com")
        XCTAssertEqual(object(calls[1].body)["token"] as? String, token, "In the body the token goes as it came")
        XCTAssertEqual(object(calls[1].body)["IsWithETF"] as? String, "Y")
        XCTAssertEqual(object(calls[2].body)["FID"] as? String, "E0024", "The company's own id, not the ETF code")
        XCTAssertEqual(object(calls[2].body)["StartDate"] as? String, "2026/11/14")
        XCTAssertEqual(object(calls[3].body)["StartDate"] as? String, "2026/11/13")
        XCTAssertEqual(object(calls[3].body)["token"] as? String, token)
    }

    func testFhtrustAsksWithSlashesAndGivesUpAfterSixDays() async throws {
        let page = "<table><tr><td>00929</td><td><a href=\"/ETF/etf_detail/ETF21#nav\">復華台灣科技優息ETF基金</a></td></tr></table>"
        let transport = FakeHoldingsTransport { call in
            if call.url.hasSuffix("/ETF/etf_list") { return Data(page.utf8) }
            guard call.url.hasSuffix("qDate=2026/11/13") else { return Data(#"{"result":[]}"#.utf8) }
            return Data(#"{"result":[{"fundID":"ETF21","etf002":"00929","dDate":"2026/11/13","detail":[{"ftype":"股票","stockid":"2357","stockname":"華碩電腦","prate_addaccint":"4.123"},{"ftype":"期貨","stockid":"WTX202611","stockname":"臺指期","prate_addaccint":"3.1"}]}]}"#.utf8)
        }
        let clock = saturday()
        let value = try await client(transport, clock).components(symbol: "00929", fundName: "復華台灣科技優息")
        XCTAssertEqual(value.components.map(\.symbol), ["2357"])
        var asked = await transport.urls()
        XCTAssertEqual(asked, ["https://www.fhtrust.com.tw/ETF/etf_list",
                               "https://www.fhtrust.com.tw/api/assets?fundID=ETF21&qDate=2026/11/14",
                               "https://www.fhtrust.com.tw/api/assets?fundID=ETF21&qDate=2026/11/13"])
        // A week later nothing parses for today or the five days before it: six tries, then the plain message.
        clock.advance(days: 7)
        let subject = client(transport, clock)
        do { _ = try await subject.components(symbol: "00929", fundName: "復華台灣科技優息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        asked = await transport.urls("api/assets")
        XCTAssertEqual(asked.suffix(6).map { String($0.suffix(10)) },
                       ["2026/11/21", "2026/11/20", "2026/11/19", "2026/11/18", "2026/11/17", "2026/11/16"])
        asked = await transport.urls("etf_list")
        XCTAssertEqual(asked.count, 1, "The fund id from a week ago was still good")
        // After a failure (and its half-hour pause) the id is asked for again, in case it was the id that went stale.
        clock.advance(days: 31.0 / 1440)
        do { _ = try await subject.components(symbol: "00929", fundName: "復華台灣科技優息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        asked = await transport.urls("etf_list")
        XCTAssertEqual(asked.count, 2)
        // A request that fails ends the search at once.
        await transport.setAnswer { call in
            if call.url.hasSuffix("/ETF/etf_list") { return Data(page.utf8) }
            throw URLError(.badServerResponse)
        }
        clock.advance(days: 31.0 / 1440)
        let before = await transport.urls("api/assets").count
        do { _ = try await subject.components(symbol: "00929", fundName: "復華台灣科技優息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let after = await transport.urls("api/assets").count
        XCTAssertEqual(after - before, 1)
    }

    func testCapitalPostsTheFundNumber() async throws {
        let transport = FakeHoldingsTransport { call in
            if call.url.hasSuffix("/etf/items") { return Data(#"{"code":200,"data":[{"fundNo":"399","stockNo":"00982A","shortName":"主動群益台灣強棒"},{"fundNo":"195","stockNo":"00919","shortName":"群益台灣精選高息"}]}"#.utf8) }
            return Data(#"{"code":200,"data":{"pcf":{"date1":"2026-11-16","date2":"2026-11-13"},"stocks":[{"stocNo":"2881","stocName":"富邦金","weight":16.1341}]}}"#.utf8)
        }
        // An active ETF: 「主動」 in front of the company's name.
        let value = try await client(transport, saturday()).components(symbol: "00982A", fundName: "主動群益台灣強棒")
        XCTAssertEqual(value.date, "2026-11-13")
        XCTAssertEqual(value.source, "群益投信")
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.method), ["POST", "POST"])
        XCTAssertEqual(calls.map(\.url), ["https://www.capitalfund.com.tw/CFWeb/api/etf/items", "https://www.capitalfund.com.tw/CFWeb/api/etf/buyback"])
        XCTAssertNil(calls[0].body, "The list is asked for without a body, as the site does")
        let body = object(calls[1].body)
        XCTAssertEqual(body["fundId"] as? String, "399")
        XCTAssertTrue(body["date"] is NSNull)
        XCTAssertEqual(body.count, 2)
    }

    func testFubonPageInBig5() async throws {
        let html = "<p>資料日期：2026/11/13</p><table><tr><td>股票代碼</td><td>股票名稱</td><td>股數</td><td>金額</td><td>權重(%)</td></tr>"
            + "<tr><td>2330</td><td>台積電</td><td>1</td><td>2</td><td>58.4473</td></tr>"
            + "<tr><td>合計</td><td></td><td>1</td><td>2</td><td>58.4473</td></tr></table>"
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        let bytes = try XCTUnwrap(html.data(using: big5))
        XCTAssertNil(String(data: bytes, encoding: .utf8), "Big5 bytes are not UTF-8")
        XCTAssertEqual(HoldingsClient.page(bytes), html)
        XCTAssertEqual(HoldingsClient.page(Data(html.utf8)), html)
        let transport = FakeHoldingsTransport { _ in bytes }
        let value = try await client(transport, saturday()).components(symbol: "006208", fundName: "富邦台50")
        XCTAssertEqual(value.components.map(\.name), ["台積電"])
        XCTAssertEqual(value.date, "2026-11-13")
        let asked = await transport.urls()
        XCTAssertEqual(asked, ["https://websys.fsit.com.tw/FubonETF/Fund/Assets.aspx?stkId=006208"])
    }

    func testEscaped() {
        XCTAssertEqual(HoldingsClient.escaped("aB+/c9== &?#"), "aB%2B%2Fc9%3D%3D%20%26%3F%23")
        XCTAssertEqual(HoldingsClient.escaped("www.ctbcinvestments.com"), "www.ctbcinvestments.com")
        XCTAssertEqual(HoldingsClient.escaped("CN"), "CN")
    }

    // MARK: Fix round 1 — pause after a failure, cancellation, what is reported

    func testFailureStartsAHalfHourPause() async throws {
        let transport = FakeHoldingsTransport { _ in throw StoreError.http(503) }
        let clock = saturday()
        let subject = client(transport, clock)
        do { _ = try await subject.components(symbol: "0050", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        // A second tap, and the app opened again: the same words, but nobody is asked and nothing more is reported.
        do { _ = try await subject.components(symbol: "0050", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        do { _ = try await client(transport, clock).components(symbol: "0050", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        clock.advance(days: 29.0 / 1440)
        do { _ = try await subject.components(symbol: "0050", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        var asked = await transport.urls()
        XCTAssertEqual(asked.count, 1, "Only the first call reached 元大")
        var failures = await reported.failures
        XCTAssertEqual(failures, [HoldingsFailure(issuer: .yuanta, kind: .http, code: 503)])
        // Another ETF is not held back by this one's pause.
        await transport.setAnswer { _ in HoldingsClientTests.yuanta("0056") }
        _ = try await subject.components(symbol: "0056", fundName: "元大高股息")
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 2)
        // After 30 minutes it tries again; a success ends the pause for good.
        clock.advance(days: 2.0 / 1440)
        await transport.setAnswer { _ in HoldingsClientTests.yuanta("0050") }
        let value = try await subject.components(symbol: "0050", fundName: "元大台灣50")
        XCTAssertEqual(value.date, "2026-11-13")
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 3)
        clock.advance(days: 1)
        await transport.setAnswer { _ in throw StoreError.http(500) }
        do { _ = try await subject.components(symbol: "0050", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 4, "The next day's first try is not held back by yesterday's pause")
        failures = await reported.failures
        XCTAssertEqual(failures.last, HoldingsFailure(issuer: .yuanta, kind: .http, code: 500))
    }

    /// The saved fund id is dropped once for a failure, not on every tap during the pause.
    func testLookupIsDroppedOncePerPause() async throws {
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("GetETFList") { return Data(#"{"result":[{"fundCode":"CN","stockCode":"00878"}],"success":true}"#.utf8) }
            return Data("<html>維護中</html>".utf8)
        }
        let clock = saturday()
        let subject = client(transport, clock)
        for _ in 0..<3 {
            do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        }
        var lists = await transport.urls("GetETFList")
        XCTAssertEqual(lists.count, 1)
        var all = await transport.urls()
        XCTAssertEqual(all.count, 2, "The list and the date, once; the two later taps asked nothing")
        clock.advance(days: 31.0 / 1440)
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        lists = await transport.urls("GetETFList")
        XCTAssertEqual(lists.count, 2, "After the pause the fund code is looked up afresh")
        all = await transport.urls()
        XCTAssertEqual(all.count, 4)
        let failures = await reported.failures
        XCTAssertEqual(failures, [HoldingsFailure(issuer: .cathay, kind: .parse), HoldingsFailure(issuer: .cathay, kind: .parse)])
    }

    /// A request that was called off is nobody's failure: no report, no pause, and the saved fund id stays.
    func testCancelledRequestIsNotAFailure() async throws {
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("GetETFList") { return Data(#"{"result":[{"fundCode":"CN","stockCode":"00878"}],"success":true}"#.utf8) }
            throw URLError(.cancelled)
        }
        let subject = client(transport, saturday(), key: true)
        do {
            _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled, "Not turned into 暫時取不到, and 富果 is not asked instead")
        }
        var failures = await reported.failures
        XCTAssertTrue(failures.isEmpty)
        // Asked again at once: the request goes out (no pause), and the fund code is still the saved one.
        await transport.setAnswer { call in
            if call.url.contains("GetETFAssets") { return Data(#"{"result":{"preDate":"2026/11/13"},"success":true}"#.utf8) }
            return Data(#"{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"}],"success":true}"#.utf8)
        }
        let value = try await subject.components(symbol: "00878", fundName: "國泰永續高股息")
        XCTAssertEqual(value.source, "國泰投信")
        let lists = await transport.urls("GetETFList")
        XCTAssertEqual(lists.count, 1)
        failures = await reported.failures
        XCTAssertTrue(failures.isEmpty)
    }

    /// A caller that gives up takes the download with it.
    func testCallerCancellationReachesTheDownload() async throws {
        let transport = FakeHoldingsTransport { _ in HoldingsClientTests.yuanta("0050") }
        // Two seconds between requests, and the first slot is taken: the next request waits, and is cancelled there.
        let reported = self.reported
        let subject = HoldingsClient(transport: transport, root: directory.appendingPathComponent("kept", isDirectory: true), defaults: defaults,
                                     minInterval: 2, clock: { Date() }, fugleKeySaved: { false },
                                     fugle: { _ in throw AppDataError("unused") }, report: { error, issuer in await reported.add(issuer, error) })
        _ = try await subject.components(symbol: "0050", fundName: "元大台灣50")
        let waiting = Task { try await subject.components(symbol: "0056", fundName: "元大高股息") }
        try await Task.sleep(nanoseconds: 200_000_000)
        waiting.cancel()
        do {
            _ = try await waiting.value
            XCTFail("Expected the cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let asked = await transport.urls()
        XCTAssertEqual(asked.count, 1, "0056 was never asked for")
        let failures = await reported.failures
        XCTAssertTrue(failures.isEmpty)
    }

    /// What goes to the reporter names the company and the kind of failure: no ETF code, no address, no answer text.
    func testReportCarriesNoCode() async throws {
        // 元大 answers with another fund: the parser's own message names it (「回應為 0056」).
        let transport = FakeHoldingsTransport { _ in HoldingsClientTests.yuanta("0056") }
        let clock = saturday()
        do { _ = try await client(transport, clock).components(symbol: "0050", fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        // A request error whose user info holds the address (ticker=00631L).
        await transport.setAnswer { call in
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: call.url, NSLocalizedDescriptionKey: "failed: " + call.url])
        }
        do { _ = try await client(transport, clock).components(symbol: "00631L", fundName: "元大台灣50正2"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let failures = await reported.failures
        XCTAssertEqual(failures, [HoldingsFailure(issuer: .yuanta, kind: .parse),
                                  HoldingsFailure(issuer: .yuanta, kind: .network, code: URLError.Code.badServerResponse.rawValue)])
        let others = await reported.others
        XCTAssertEqual(others, 0, "Only HoldingsFailure is ever reported")
        for failure in failures {
            let error = failure as NSError
            let text = [failure.localizedDescription, String(describing: failure), String(reflecting: failure),
                        error.domain, error.description, String(describing: error.userInfo)].joined(separator: " | ")
            for code in ["0050", "0056", "00631L", "ticker", "yuantaetfs"] {
                XCTAssertFalse(text.contains(code), "\(code) in \(text)")
            }
            XCTAssertEqual(error.domain, "ETFToGo.Holdings")
        }
        // No network at all is the phone's trouble: not reported (as for every other load).
        await transport.setAnswer { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client(transport, clock).components(symbol: "0056", fundName: "元大高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let after = await reported.failures
        XCTAssertEqual(after.count, 2)
    }

    /// No connection is not the company's failure: no pause starts and the saved fund id stays, so the next call, with
    /// the network back, goes out at once.
    func testOfflineFailureStartsNoPause() async throws {
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("GetETFList") { return Data(#"{"result":[{"fundCode":"CN","stockCode":"00878"}],"success":true}"#.utf8) }
            throw URLError(.notConnectedToInternet)
        }
        let clock = saturday()
        let subject = client(transport, clock)
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        var asked = await transport.urls()
        XCTAssertEqual(asked.count, 2, "The list, then the date, which found no network")
        // The network is back and the same ETF is asked for straight away: the transport is called again.
        await transport.setAnswer { call in
            if call.url.contains("GetETFAssets") { return Data(#"{"result":{"preDate":"2026/11/13"},"success":true}"#.utf8) }
            return Data(#"{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"}],"success":true}"#.utf8)
        }
        let value = try await subject.components(symbol: "00878", fundName: "國泰永續高股息")
        XCTAssertEqual(value.source, "國泰投信")
        asked = await transport.urls()
        XCTAssertEqual(asked.count, 4, "No half-hour pause after an offline failure")
        let lists = await transport.urls("GetETFList")
        XCTAssertEqual(lists.count, 1, "The saved fund code was kept")
        let failures = await reported.failures
        XCTAssertTrue(failures.isEmpty, "Nothing is reported for a phone without a connection")
        // A company's own failure right after still starts the pause.
        clock.advance(days: 1)
        await transport.setAnswer { _ in throw StoreError.http(503) }
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let before = await transport.urls().count
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let after = await transport.urls().count
        XCTAssertEqual(after, before, "Paused: nobody is asked")
    }

    /// A timeout, a failed DNS lookup, a refused or dropped connection: the company's site may be down, so the pause
    /// starts and the next tap asks nobody. None of them is reported (the phone could not reach the server).
    func testUnreachableCompanyStartsThePause() async throws {
        for (i, code) in [URLError.Code.timedOut, .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost].enumerated() {
            let symbol = "005\(i)"
            let transport = FakeHoldingsTransport { _ in throw URLError(code) }
            let clock = saturday()
            let subject = client(transport, clock)
            do { _ = try await subject.components(symbol: symbol, fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
            do { _ = try await subject.components(symbol: symbol, fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
            var asked = await transport.urls()
            XCTAssertEqual(asked.count, 1, "\(code): the second call makes no request")
            // Half an hour later it asks again.
            clock.advance(days: 31.0 / 1440)
            do { _ = try await subject.components(symbol: symbol, fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
            asked = await transport.urls()
            XCTAssertEqual(asked.count, 2, "\(code): asked again after the pause")
        }
        let failures = await reported.failures
        XCTAssertTrue(failures.isEmpty, "A server the phone could not reach is not reported")
    }

    /// The saved fund id goes with a timeout as with any other failure: after the pause it is looked up afresh.
    func testTimeoutDropsTheLookup() async throws {
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("GetETFList") { return Data(#"{"result":[{"fundCode":"CN","stockCode":"00878"}],"success":true}"#.utf8) }
            throw URLError(.timedOut)
        }
        let clock = saturday()
        let subject = client(transport, clock)
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        var all = await transport.urls()
        XCTAssertEqual(all.count, 2, "The list and the date that timed out; the second call asked nothing")
        clock.advance(days: 31.0 / 1440)
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let lists = await transport.urls("GetETFList")
        XCTAssertEqual(lists.count, 2)
        all = await transport.urls()
        XCTAssertEqual(all.count, 4)
    }

    /// The phone's own "no network": the request says so (not connected, or mobile data off for the app), or the app
    /// knows it is offline whatever error the request came back with. No pause: the second call asks again.
    func testPhoneWithoutNetworkStartsNoPause() async throws {
        for (i, code) in [URLError.Code.notConnectedToInternet, .dataNotAllowed].enumerated() {
            let symbol = "005\(i)"
            let transport = FakeHoldingsTransport { _ in throw URLError(code) }
            let subject = client(transport, saturday())
            do { _ = try await subject.components(symbol: symbol, fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
            do { _ = try await subject.components(symbol: symbol, fundName: "元大台灣50"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
            let asked = await transport.urls()
            XCTAssertEqual(asked.count, 2, "\(code): the second call makes a request")
        }
        // 離線中 with a request that only timed out: still the phone's trouble.
        let transport = FakeHoldingsTransport { call in
            if call.url.contains("GetETFList") { return Data(#"{"result":[{"fundCode":"CN","stockCode":"00878"}],"success":true}"#.utf8) }
            throw URLError(.timedOut)
        }
        let subject = client(transport, saturday(), offline: true)
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        do { _ = try await subject.components(symbol: "00878", fundName: "國泰永續高股息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        let all = await transport.urls()
        XCTAssertEqual(all.count, 3, "No pause: the date is asked for again")
        let lists = await transport.urls("GetETFList")
        XCTAssertEqual(lists.count, 1, "The saved fund code was kept")
        let failures = await reported.failures
        XCTAssertTrue(failures.isEmpty)
    }

    // MARK: Fix round 1 — the history has its own file

    private func bigHistory(funds: Int) -> [String: [ComponentSnapshot]] {
        let stocks = (0..<1000).map { FundComponent(symbol: String(format: "S%04d", $0), name: String(format: "成分%04d", $0), weight: 0.1) }
        var history: [String: [ComponentSnapshot]] = [:]
        for fund in 0..<funds {
            let code = String(format: "009%02d", fund)
            history[code] = (1...12).reversed().map { ComponentSnapshot(symbol: code, date: String(format: "2026-09-%02d", $0), components: stocks, source: "test") }
        }
        return history
    }

    @MainActor func testLargeHistoryDoesNotBlockSaves() throws {
        let url = directory.appendingPathComponent("p.json")
        let store = PortfolioStore(url: url)
        var next = store.data
        next.componentHistory = bigHistory(funds: 10)
        XCTAssertGreaterThan(try JSONEncoder().encode(next).count, 5_000_000, "More than the records may weigh")
        try store.commit(next)
        // Everything else still saves.
        try store.save(Portfolio.sample.holdings[0])
        try store.saveComponents(snapshot("0050", "2026-10-01"))
        let records = try Data(contentsOf: url)
        XCTAssertLessThan(records.count, 100_000, "The records file does not carry the history")
        XCTAssertFalse(String(decoding: records, as: UTF8.self).contains("componentHistory"))
        XCTAssertGreaterThan(try Data(contentsOf: url.appendingPathExtension("holdings")).count, 5_000_000)
        // It is all there when the app opens again.
        let reopened = PortfolioStore(url: url)
        XCTAssertNil(reopened.message)
        XCTAssertEqual(reopened.data.holdings.count, 1)
        XCTAssertEqual(reopened.data.componentHistory?.count, 11)
        XCTAssertEqual(reopened.componentHistory(for: "00907").map(\.date), (1...12).reversed().map { String(format: "2026-09-%02d", $0) })
        XCTAssertEqual(reopened.componentHistory(for: "00907").first?.components.count, 1000)
        XCTAssertEqual(reopened.componentHistory(for: "0050").map(\.date), ["2026-10-01"])
        try reopened.save(Portfolio.sample.holdings[1])
        // A backup must stay importable (5 MB): it keeps the newest days of each ETF that fit.
        let backup = try Data(contentsOf: reopened.export())
        XCTAssertLessThanOrEqual(backup.count, 5_000_000)
        let other = PortfolioStore(url: directory.appendingPathComponent("other.json"))
        try other.importBackup(backup)
        XCTAssertEqual(other.data.holdings.count, 2)
        XCTAssertEqual(other.componentHistory(for: "00907").map(\.date), (7...12).reversed().map { String(format: "2026-09-%02d", $0) })
        XCTAssertEqual(other.componentHistory(for: "0050").map(\.date), ["2026-10-01"])
    }

    /// A records file from the build that kept the history inside it: read as it is, moved to its own file by the next save.
    @MainActor func testHistoryMovesOutOfAnOldRecordsFile() throws {
        let url = directory.appendingPathComponent("old.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var old = Portfolio()
        old.remember(snapshot("0050", "2026-09-01"))
        old.remember(snapshot("0050", "2026-09-02"))
        old.components = ["0050": snapshot("0050", "2026-09-02")]
        try JSONEncoder().encode(old).write(to: url)
        let side = url.appendingPathExtension("holdings")
        let store = PortfolioStore(url: url)
        XCTAssertNil(store.message)
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), ["2026-09-02", "2026-09-01"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: side.path), "Opening the app writes nothing")
        try store.save(Portfolio.sample.holdings[0])
        XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("componentHistory"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: side.path))
        let reopened = PortfolioStore(url: url)
        XCTAssertEqual(reopened.componentHistory(for: "0050").map(\.date), ["2026-09-02", "2026-09-01"])
        XCTAssertEqual(reopened.data.components?["0050"]?.date, "2026-09-02")
        try reopened.saveComponents(snapshot("0050", "2026-09-03"))
        XCTAssertEqual(PortfolioStore(url: url).componentHistory(for: "0050").map(\.date), ["2026-09-03", "2026-09-02", "2026-09-01"])
        // A history file that cannot be read costs the history only, never the records.
        try Data("not json".utf8).write(to: side)
        let damaged = PortfolioStore(url: url)
        XCTAssertNil(damaged.message)
        XCTAssertEqual(damaged.data.holdings.count, 1)
        XCTAssertTrue(damaged.componentHistory(for: "0050").isEmpty)
    }
}
