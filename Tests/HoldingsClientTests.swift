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

/// Which fund companies' failures were reported.
private actor Reported {
    private(set) var issuers: [Issuer] = []
    func add(_ issuer: Issuer) { issuers.append(issuer) }
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

    private func client(_ transport: FakeHoldingsTransport, _ clock: HoldingsClock, key: Bool = false) -> HoldingsClient {
        let reported = self.reported
        return HoldingsClient(transport: transport, root: directory.appendingPathComponent("kept", isDirectory: true), defaults: defaults,
                              minInterval: 0, clock: { clock.now }, fugleKeySaved: { key },
                              fugle: { symbol in
                                  ComponentSnapshot(symbol: symbol, date: "2026-11-12", components: [FundComponent(symbol: "2330", name: "台積電", weight: 30)], source: "富果／投信揭露資料")
                              },
                              report: { _, issuer in await reported.add(issuer) })
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
        let subject = client(transport, saturday())
        do { try await store.refreshComponents("0050", client: subject); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        XCTAssertEqual(store.data.components?["0050"]?.date, "2026-11-10")
        XCTAssertEqual(store.componentHistory(for: "0050").map(\.date), ["2026-11-10"])
        let asked = await transport.urls()
        XCTAssertEqual(asked.count, 1, "0050 is 元大's (the name in the ETF list), so 元大 was asked")
        let issuers = await reported.issuers
        XCTAssertEqual(issuers, [.yuanta], "The failure is reported under the fund company alone")
        // A body that is not the company's JSON is the same failure.
        await transport.setAnswer { _ in Data("<html>維護中</html>".utf8) }
        do { try await store.refreshComponents("0050", client: subject); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
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
        // After a failure the id is asked for again, in case it was the id that went stale.
        do { _ = try await subject.components(symbol: "00929", fundName: "復華台灣科技優息"); XCTFail("Expected an error") } catch { expect(error, "暫時取不到，稍後再試") }
        asked = await transport.urls("etf_list")
        XCTAssertEqual(asked.count, 2)
        // A request that fails ends the search at once.
        await transport.setAnswer { call in
            if call.url.hasSuffix("/ETF/etf_list") { return Data(page.utf8) }
            throw URLError(.badServerResponse)
        }
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
}
