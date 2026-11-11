# P0-1 PocketCore 核心套件與官方資料 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 App 內不依賴畫面的邏輯搬進可在 Linux 與 Mac 測試的 Swift Package `PocketCore`，並新增免金鑰的官方收盤價與除權息預告解析，作為 P0 其餘部分（3D 設計系統、新畫面）的基礎。

**Architecture:** `PocketCore/` 是無第三方相依的 Swift Package（Foundation only）。資料模型、備份格式、CSV／券商匯入、研究計算、ETF 名單與年度費用解析、富果回應解析、官方資料解析都在這裡，App 只保留畫面、`PortfolioStore`、Keychain 與網路傳輸。兩個平台共用的測試資料放 `SharedFixtures/`。

**Tech Stack:** Swift 6.1 toolchain、Swift language mode 5、XCTest、XcodeGen（App 端）。

**Spec:** `docs/superpowers/specs/2026-11-11-etf-pocket-redesign-design.md`（第 4 節 P0、第 5.1 與 5.3 節）

**P0 拆成三份計畫：** P0-1（本計畫，可在 Linux 驗證）→ P0-2 3D 設計系統（需 Mac）→ P0-3 五個分頁以新視覺重做（需 Mac）。

## Global Constraints

- Linux 測試指令：`export PATH=/opt/swift-dl/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin:$PATH && swift test --package-path PocketCore`
- `Package.swift`：`// swift-tools-version: 5.10`，`platforms: [.iOS(.v18), .macOS(.v14)]`，`swiftLanguageVersions: [.v5]`，沒有任何外部 dependency。
- App 最低版本改為 iOS 18.0（spec D7）。
- `PocketCore` 不得 import `SwiftUI`、`Combine`、`Security`、`CryptoKit`、`UIKit`；Apple 專屬功能用 `#if canImport(Darwin)` 包住。
- App 會用到的型別、屬性、初始化器、方法都要 `public`；struct 需補 `public init`（memberwise init 不會自動公開）。
- 使用者看得到的錯誤文字一字不改（繁體中文）。
- 備份 `schema` 維持 1；`StableID` 產生的 UUID 必須與原 CryptoKit 版本逐位元組相同，舊資料的識別碼不能變。
- 日期一律以 `Asia/Taipei` 解讀，格式 `yyyy-MM-dd`；民國日期用既有 `DataChecks.rocDay`。
- 官方資料只用三個已實測可用的端點（2026-11-11）：`https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL`、`https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes`、`https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL`。
- 每個 task 結束時 `swift test --package-path PocketCore` 全部通過才 commit。

## Review Focus

1. **沒有成交的列**（證交所 `ClosingPrice` 為空字串、櫃買 `Close` 為 `" ---"`）→ 跳過，絕不產生價格 0 的報價。→ Task 5 測試 `testNoTradeRowsAreSkipped`。
2. **外幣級別代碼**（結尾 `K`、`C`）的收盤價 → `currency` 設為 `"UNKNOWN"`，不得算進台幣市值。→ Task 5 測試 `testForeignClassIsNotTWD`。
3. **除權息預告沒有寫現金股利**（`CashDividend` 為空）→ `cashPerShare == nil`，不是 0。→ Task 6 測試 `testMissingCashDividendIsNil`。
4. **官方收盤價比手上的報價舊**（例如富果盤中報價日期較新）→ 不覆寫；日期相同時保留既有。→ Task 5 測試 `testMergeKeepsNewerQuote`。
5. **舊資料識別碼**：純 Swift SHA-256 對中文與 `\u{0}` 分隔字串的結果要與原實作一致。→ Task 1 測試 `testStableIDMatchesLegacyValues`。

---

### Task 1: 套件骨架、SHA-256、StableID、DataChecks

**Files:**
- Create: `PocketCore/Package.swift`
- Create: `PocketCore/Sources/PocketCore/Support/SHA256.swift`
- Create: `PocketCore/Sources/PocketCore/Support/StableID.swift`（自 `App/LegacyImport.swift` 移入）
- Create: `PocketCore/Sources/PocketCore/Support/DataChecks.swift`（自 `App/Catalog.swift` 移入 `AppDataError` 與 `DataChecks`，**不含** `readFile`）
- Test: `PocketCore/Tests/PocketCoreTests/SupportTests.swift`

**Interfaces:**
- Produces: `public enum SHA256Digest { public static func hash(_ data: Data) -> [UInt8] }`；`public enum StableID { public static func make(_ namespace: String, _ value: String) -> UUID }`；`public struct AppDataError: LocalizedError { public init(_ text: String) }`；`public enum DataChecks { code(_:) -> Bool; day(_:) -> String; date(_:) -> Date?; rocDay(_:) -> String? }`（全部 `public static`，行為與現有相同）。

- [ ] **Step 1: 寫失敗測試**

```swift
func testSHA256KnownVectors() {
    XCTAssertEqual(hex(SHA256Digest.hash(Data("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    XCTAssertEqual(hex(SHA256Digest.hash(Data())), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    XCTAssertEqual(hex(SHA256Digest.hash(Data("代碼".utf8))), "e4cf7624ee98d7a86f74171a55fa5f7afebd727c9986b7b23c05b5edcfe36e8b")
    XCTAssertEqual(hex(SHA256Digest.hash(Data(repeating: 0x61, count: 1_000))).count, 64) // multi-block path
}
func testStableIDMatchesLegacyValues() {
    XCTAssertEqual(StableID.make("legacy-holding", "pwa-001").uuidString, "5FEF0885-6A6B-555C-8BEC-451862548983")
    XCTAssertEqual(StableID.make("broker-account", "富邦證券\u{0}主帳戶").uuidString, "BC7184A2-8615-5B96-BBEF-6ACB785C7D4E")
}
func testDataChecksDatesAndCodes() {
    XCTAssertEqual(DataChecks.rocDay("1151110"), "2026-11-10")
    XCTAssertNil(DataChecks.date("2026-02-30"))
    XCTAssertTrue(DataChecks.code("00679B")); XCTAssertFalse(DataChecks.code("AAPL"))
}
```
（`hex` 為測試檔內的小工具：`bytes.map { String(format: "%02x", $0) }.joined()`。另加一個 1,000 位元組 `a` 的完整雜湊值，實作時用 `python3 -c "import hashlib;print(hashlib.sha256(b'a'*1000).hexdigest())"` 取得後寫死。）

- [ ] **Step 2: 執行測試確認失敗**（`swift test --package-path PocketCore`，預期：找不到 `SHA256Digest` 等符號）
- [ ] **Step 3: 實作** — `SHA256Digest.hash` 為標準 FIPS 180-4 純 Swift 實作；`StableID.make` 與原碼相同，只把 `SHA256.hash` 換成 `SHA256Digest.hash`；`DataChecks` 原樣移入並加 `public`。
- [ ] **Step 4: 執行測試確認通過**
- [ ] **Step 5: Commit** `feat(core): add PocketCore package with SHA-256, StableID and DataChecks`

---

### Task 2: 資料模型與備份格式

**Files:**
- Create: `PocketCore/Sources/PocketCore/Models/Portfolio.swift`（`Strategy`、`Fund`、`Holding`、`DividendStatus`、`Dividend`、`Quote`、`Portfolio`、`StoreError`，自 `App/Models.swift` 移入）
- Create: `PocketCore/Sources/PocketCore/Models/Planning.swift`（`Projection`、`LegacyPlan`、`LegacyPrice`，以及 `App/PlanView.swift` 的 `PlanMath`、`PlanYear`）
- Test: `PocketCore/Tests/PocketCoreTests/PortfolioModelTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `DataChecks`、`AppDataError`。
- Produces: 上述型別全部 `public`，欄位名稱與 Codable 鍵不變。`Strategy.symbol` 保留（SF Symbol 名稱字串，不需 SwiftUI）。`StoreError.keychain` 的參數由 `OSStatus` 改為 `Int32`（Linux 沒有 `OSStatus`；兩者同為 32 位元整數，App 端呼叫不必轉型）。`Portfolio.decodeBackup(_:)`、`Portfolio.demo`、`PlanMath.project(_:) throws -> [PlanYear]` 行為不變。

- [ ] **Step 1: 寫失敗測試** — 從 `Tests/PortfolioTests.swift` 移入 `testNoMarketValueWithoutCompleteQuotes`（期望 348500）、`testProjectionZeroReturnAndMonthlyTiming`、`testBackupRejectsInvalidData`；從 `Tests/RestoredFeaturesTests.swift` 移入 `testSchemaOneStillDecodesWithoutNewFields`、`testPlanReinvestmentDoesNotCountDividendsTwice`。斷言與數值不改，只把 `@testable import ETFToGo` 換成 `@testable import PocketCore`。
- [ ] **Step 2: 執行確認失敗**
- [ ] **Step 3: 實作** — 原樣搬移並加 `public`；`Portfolio` 內 `components`、`histories`、`fees` 型別在 Task 4 才搬入，本 task 先一起搬 `FundComponent`、`ComponentSnapshot`（含 `imported(_:symbol:)`）、`PricePoint`、`PriceHistory`、`FeeRecord` 的**型別宣告與 `validate()`** 到 `Models/ResearchModels.swift`，計算邏輯留到 Task 4。
- [ ] **Step 4: 執行確認通過**
- [ ] **Step 5: Commit** `feat(core): move portfolio models, backup format and planning math`

---

### Task 3: 舊備份匯入、CSV 與券商匯入

**Files:**
- Create: `PocketCore/Sources/PocketCore/Import/BackupImport.swift`（自 `App/LegacyImport.swift`）
- Create: `PocketCore/Sources/PocketCore/Import/CSVTable.swift`、`BrokerPreview.swift`（自 `App/BrokerImport.swift`，`BrokerMapping` 一併移入；`PortfolioStore.importBroker` 留在 App）
- Test: `PocketCore/Tests/PocketCoreTests/ImportTests.swift`

**Interfaces:**
- Produces: `public enum BackupImport { public static func decode(_ bytes: Data) throws -> Portfolio }`；`public struct CSVTable { headers, rows; public static func parse(_ bytes: Data) throws -> CSVTable; public func guess(_ names: [String]) -> Int }`；`public struct BrokerMapping`（含 `public init(symbol:name:shares:cost:lots:totalCost:)`，預設值不變）；`public struct BrokerPreview { holdings, sourceAccount, broker, totalCost; public static func make(table:mapping:broker:account:funds:) throws -> BrokerPreview }`。

- [ ] **Step 1: 寫失敗測試** — 移入 `testRealPWAShapeMigratesCostActualDividendAndMetadata`、`testPlannedDividendAndOlderNativeEnvelope`、`testLegacyRejectsNegativeCostsAndMissingActualPayment`、`testCSVQuotedCommasNewlinesAndTrailingLine`、`testCSVAcceptsBOMBeforeQuotedHeader`、`testCSVUTF16AndBig5Encoding`（Big5 段落包在 `#if canImport(Darwin)`）。新增：

```swift
func testBrokerPreviewConvertsLotsAndUsesStableIDs() throws {
    let table = try CSVTable.parse(Data("代碼,張數,總成本\n0050,2,100000".utf8))
    let funds = [Fund(id: "0050", name: "元大台灣50", strategy: .saving)]
    let a = try BrokerPreview.make(table: table, mapping: BrokerMapping(symbol: 0, name: -1, shares: 1, cost: 2, lots: true, totalCost: true), broker: "富邦證券", account: "主帳戶", funds: funds)
    XCTAssertEqual(a.holdings[0].shares, 2000); XCTAssertEqual(a.holdings[0].unitCost, 50)
    XCTAssertEqual(a.sourceAccount, "BC7184A2-8615-5B96-BBEF-6ACB785C7D4E")
    let b = try BrokerPreview.make(table: table, mapping: BrokerMapping(symbol: 0, name: -1, shares: 1, cost: 2, lots: true, totalCost: true), broker: "富邦證券", account: "主帳戶", funds: funds)
    XCTAssertEqual(a.holdings[0].id, b.holdings[0].id)
}
```
- [ ] **Step 2: 執行確認失敗**
- [ ] **Step 3: 實作** — 原樣搬移並公開；`CSVTable.parse` 的 Big5 解碼放在 `#if canImport(Darwin)`，Linux 上 UTF-8 失敗時直接丟出原本的「請將對帳單另存為 UTF-8 CSV。」。
- [ ] **Step 4: 執行確認通過**
- [ ] **Step 5: Commit** `feat(core): move backup, CSV and broker import`

---

### Task 4: 研究計算、ETF 名單、年度費用、富果回應解析

**Files:**
- Create: `PocketCore/Sources/PocketCore/Analytics/ResearchMath.swift`（`ExposureRow`、`OverlapRow`、`ResearchMath`、`PerformanceStats`；`FundComponent`、`PricePoint` 已於 Task 2 移入）
- Create: `PocketCore/Sources/PocketCore/Sources/Catalog.swift`（`CatalogSnapshot`、`CatalogAPI.decode`／`strategy`／三個 URL 常數）
- Create: `PocketCore/Sources/PocketCore/Sources/AnnualFees.swift`（`AnnualExpense`、`AnnualFeeCatalog`）
- Create: `PocketCore/Sources/PocketCore/Sources/FugleDecode.swift`
- Move: `App/Resources/catalog.json`、`App/Resources/annual-fees.json` → `PocketCore/Sources/PocketCore/Resources/`（`Package.swift` 以 `.process("Resources")` 宣告）
- Test: `PocketCore/Tests/PocketCoreTests/ResearchTests.swift`

**Interfaces:**
- Produces: `CatalogSnapshot.bundled()` 與 `AnnualFeeCatalog.bundled` 改讀 `Bundle.module`；`public enum FugleDecode { quote(_:expectedSymbol:) throws -> Quote; components(_:symbol:) throws -> ComponentSnapshot; history(_:symbol:) throws -> [PricePoint] }`，內容即原 `Fugle.decode`、`Fugle.decodeComponents`、`Fugle.decodeHistory`。網路抓取（`Fugle.quote`、`Fugle.history`、`CatalogAPI.fetch`）留在 App 並改呼叫這些函式。

- [ ] **Step 1: 寫失敗測試** — 移入 `testQuoteValidation`（改呼叫 `FugleDecode.quote`）、`testBundledCatalogCoversBothMarketsAndNoDuplicateCodes`、`testCatalogRejectsMissingMarketAndDuplicates`、`testCatalogExcludesHistoricalAndFutureListings`、`testOverlapAndExposureUseWeightsAndExcludeMissingQuotes`、`testComponentsRejectFutureDatesInvalidWeightsAndUnknownSymbol`、`testPricePerformanceUsesDrawdownsAndRealTimeInterval`、`testHistoryRejectsUnadjustedDataAndDuplicateDates`、`testFeeRecordRequiresYearAndSource`、`testAnnualFeeSnapshotUsesReportedTotalsAndCorrectYear`。斷言不改。
- [ ] **Step 2: 執行確認失敗**
- [ ] **Step 3: 實作** — 原樣搬移並公開；資源改用 `Bundle.module`。
- [ ] **Step 4: 執行確認通過**（此時原 26 項中所有不依賴 `PortfolioStore` 的測試都已在套件內通過）
- [ ] **Step 5: Commit** `feat(core): move research math, catalogue, annual fees and Fugle decoding`

---

### Task 5: 官方每日收盤價

**Files:**
- Create: `SharedFixtures/official/twse-stock-day-all.json`（自 2026-11-11 實際回應擷取 `0050`、`00878`、`00625K`（無成交）、`00635U`、`2330`（非 ETF）五列，欄位原樣）
- Create: `SharedFixtures/official/tpex-daily-close.json`（擷取 `00679B`、`00411A`、`00986B`（`Close` 為 `" ---"`）、一檔非 `00` 開頭股票）
- Create: `SharedFixtures/official/expected-quotes.json`（兩份輸入合併後的預期 `[{symbol, price, date, currency}]`，依 symbol 排序）
- Create: `PocketCore/Sources/PocketCore/Sources/OfficialQuotes.swift`
- Test: `PocketCore/Tests/PocketCoreTests/OfficialQuotesTests.swift`（以 `#filePath` 往上找到 repo 根目錄讀 `SharedFixtures`）

**Interfaces:**
- Consumes: `Quote`、`DataChecks.rocDay`、`DataChecks.code`。
- Produces:
  - `public enum OfficialQuotes`
  - `public static let source = "證交所／櫃買中心盤後收盤價"`
  - `public static func decodeTWSE(_ bytes: Data, fetchedAt: Date) throws -> [Quote]`
  - `public static func decodeTPEx(_ bytes: Data, fetchedAt: Date) throws -> [Quote]`
  - `public static func merge(_ incoming: [Quote], into existing: [String: Quote]) -> [String: Quote]`

規則：只收 `DataChecks.code` 通過且以 `00` 開頭的代碼；收盤價去空白後須能轉成大於 0 的有限數字，否則跳過；`date` 由民國日期轉為 `yyyy-MM-dd`，轉換失敗整份丟 `AppDataError("官方收盤價日期格式改變，保留原有報價。")`；代碼結尾為 `K`、`C` 時 `currency = "UNKNOWN"`（`U` 為以台幣交易的期貨型 ETF，屬 TWD；見 ledger ruling），其餘 `"TWD"`；`changePercent = nil`。`merge` 只在新報價 `date` 嚴格大於既有報價時取代，沒有既有報價時直接加入。

- [ ] **Step 1: 寫失敗測試** — `testDecodeMatchesSharedExpectation`（兩份 fixture 解析結果等於 `expected-quotes.json`）、`testNoTradeRowsAreSkipped`（`00625K`、`00986B` 不在結果中）、`testForeignClassIsNotTWD`（`00636K`、`00687C` 的 `isTWD == false`，`00635U`、`0050` 的 `isTWD == true`）、`testMergeKeepsNewerQuote`（既有 `2026-11-11` 不被 `2026-11-10` 取代；既有 `2026-11-07` 被取代；日期相同保留既有）、`testChangedDateFormatThrows`（`Date` 改成 `"2026/11/10"` 時丟錯）。
- [ ] **Step 2: 執行確認失敗**
- [ ] **Step 3: 實作 `OfficialQuotes`**
- [ ] **Step 4: 執行確認通過**
- [ ] **Step 5: Commit** `feat(core): parse official TWSE and TPEx closing prices`

---

### Task 6: 官方除權息預告

**Files:**
- Create: `SharedFixtures/official/twse-twt48u.json`（擷取 `00690`（現金股利 2.000000）、`0051`（現金股利空白）、一列 `權`、一檔非 ETF）
- Create: `SharedFixtures/official/expected-ex-dividends.json`
- Create: `PocketCore/Sources/PocketCore/Sources/OfficialDividends.swift`
- Test: `PocketCore/Tests/PocketCoreTests/OfficialDividendsTests.swift`

**Interfaces:**
- Produces:
  - `public struct ExDividendNotice: Codable, Equatable { public var symbol: String; public var name: String; public var exDate: String; public var kind: Kind; public var cashPerShare: Double? }`
  - `public enum Kind: String, Codable { case cash = "息", stock = "權", both = "權息" }`
  - `public enum OfficialDividends { public static func decodeTWT48U(_ bytes: Data, etfCodes: Set<String>) throws -> [ExDividendNotice] }`
  - 結果依 `exDate`、`symbol` 排序。

- [ ] **Step 1: 寫失敗測試** — `testDecodeMatchesSharedExpectation`、`testMissingCashDividendIsNil`（`0051` 的 `cashPerShare == nil`）、`testOnlyCatalogueETFsAreKept`（非 ETF 與不在 `etfCodes` 的代碼被排除）、`testUnknownKindThrows`（`Exdividend` 為未知值時丟 `AppDataError("除權息資料欄位改變，未更新。")`）。
- [ ] **Step 2: 執行確認失敗**
- [ ] **Step 3: 實作 `OfficialDividends`**
- [ ] **Step 4: 執行確認通過**
- [ ] **Step 5: Commit** `feat(core): parse official ex-dividend pre-announcements`

---

### Task 7: App 改用 PocketCore

**Files:**
- Modify: `project.yml`（`deploymentTarget.iOS: '18.0'`；新增 `packages: { PocketCore: { path: PocketCore } }`；`ETFToGo` 與 `ETFToGoTests` 加 `dependencies: [{ package: PocketCore }]`）
- Modify: `App/Models.swift`、`App/Catalog.swift`、`App/BrokerImport.swift`、`App/ResearchData.swift`、`App/AnnualFees.swift`、`App/LegacyImport.swift`、`App/PlanView.swift`：刪除已搬走的宣告，檔頭加 `import PocketCore`；保留 `PortfolioStore`、`SecureKey`、`PublicHTTP`、`Fugle` 網路函式、`CatalogAPI.fetch`、`PortfolioStore.importBroker`、`DataChecks.readFile`（改名為 `FileAccess.read(_:limit:)` 放在 `App/Catalog.swift`）
- Delete: `App/Resources/`（已搬入套件）
- Modify: `Tests/PortfolioTests.swift`、`Tests/RestoredFeaturesTests.swift`：只保留需要 `PortfolioStore` 的 5 項（`testPersistenceAndImportIdempotence`、`testMalformedFileIsNotOverwritten`、`testPWARepeatedImportKeepsCurrentDataAndStableIDs`、`testBrokerReimportReplacesOnlySelectedAccount`、`testBackupRestoresQuotesWithoutOverwritingExistingQuotes`），加 `import PocketCore`；其餘 21 項已在 Task 2–4 移入套件
- Modify: `README.md` 建置章節：最低 iOS 18、`PocketCore` 的 Linux 測試指令

**Interfaces:**
- Consumes: Task 1–6 的全部公開 API。

- [ ] **Step 1: 搬移後在 Linux 執行** `swift test --package-path PocketCore`，預期全部通過。
- [ ] **Step 2: 確認 App 內沒有重複宣告**：`grep -rn "struct Holding\|enum StableID\|struct CSVTable\|enum ResearchMath" App` 應無輸出。
- [ ] **Step 3: 在 Mac 驗證**（本環境無法執行）：`xcodegen generate && xcodebuild test -scheme ETFToGo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，預期編譯成功、App 端 5 項測試與 UI 測試通過。若 GitHub Actions 預算或 Mac 不可用，這一步標記為「待驗證」，不得宣稱 App 已可編譯。
- [ ] **Step 4: Commit** `refactor(app): use PocketCore package and require iOS 18`

---

## Self-Review 紀錄

- Spec 覆蓋：5.1 工程結構（PocketCore、SharedFixtures）→ Task 1–4、7；5.3 官方收盤價 → Task 5；P3 會用到的除權息預告 → Task 6（提前做解析，同步與提醒仍在 P3）；D7 iOS 18 → Task 7。3D 設計系統與新畫面不在本計畫，見 P0-2、P0-3。
- 已知限制：Linux 無 Big5 轉碼，Big5 測試只在 Mac 執行；App 編譯需 Mac。
