# 口袋會員功能擴充 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make 口袋會員 worth paying for: a member gate, then member-only overlap, active-ETF tracking, scenarios, a goal planner, monthly/annual reports, backtests and price alerts — all on-device, from free official and fund-company data.

**Architecture:** Pure logic (parsers, engines, gate rules) goes in `PocketCore` (tested on Linux with `swift test`); networking, storage and SwiftUI screens go in `App/` (tested in the simulator). Every member screen is wrapped in one shared `MemberLock` view; every new fetcher is cached on the phone and sends only ETF codes.

**Tech Stack:** Swift 6 toolchain (Swift 5 language mode), SwiftUI, iOS 18+, StoreKit 2, `BackgroundTasks`, `UserNotifications`, XcodeGen (`project.yml`), GitHub Actions `native-ui.yml` (jobs core, simulator, skin-matrix). No local Swift toolchain: every test run is a CI run.

**Spec:** `docs/superpowers/specs/2026-11-13-pocket-member-features-design.md` (approved 2026-11-13). Data-source facts: Appendix A of this plan; raw samples in `SharedFixtures/member/`.

## Global Constraints

- Branch `claude/pocket-member-features`; push there only. No merge to main, no TestFlight, no App Review submission without asking.
- Data only from: TWSE/TPEx official endpoints, the six fund companies' public holdings endpoints (Appendix A), and Fugle only when the user entered a key. Requests carry only ETF codes and dates — never holdings, amounts or alerts.
- No server. No new third-party packages.
- Non-members keep everything that is free today except: 重疊成分 tab, combo scenarios other than 基準, and the new features. Free stays free: 記帳、配息、除息提醒、圖鑑、定期定額試算、股息複利、領息目標試算、費用比較、券商匯入、持股集中度.
- Copy rules: calculators say 「情境試算，不是預測或保證」; backtest adds 「過去績效不代表未來」; alerts say 「沒有富果金鑰時，以每日收盤價判斷；iPhone 會在背景不定時檢查，不保證即時。」
- `--demo-member` works only together with `--ui-testing` and wins over the real StoreKit state.
- When membership lapses: features lock again, price alerts stop notifying (checked at fire time), saved alerts/snapshots/backtest settings are kept.
- All new UI uses the skin kit (`Page`, `SkinCard`, `skinFont`, `skinForeground`) and Traditional Chinese copy.
- Pricing/yearly products are out of scope; `MembershipProducts` is unchanged.
- Fund-company fetch failures never crash or show partial data: show 「暫時取不到，稍後再試」 and report through the existing load-failure reporter (`CrashReporting` LoadFailed path).
- Each fund-company and official endpoint: at most one fetch per symbol per day for holdings; official history throttled to 1 request / 2 s; past months cached permanently.

## Review Focus

1. **ETF that split mid-backtest (0050 on 2025-06-18, ratio 4):** the curve must not show a fake −75% drop; shares multiply by the ratio. → Task 5 test `testSplitDoesNotLookLikeACrash`.
2. **ETF listed after the chosen start year:** its contributions start at its first trading month and the result carries a note. → Task 5 test `testLateListingStartsAtFirstBar`.
3. **Fund-company response that is valid JSON but empty or reshaped (site redesign):** parser throws, the app shows 「暫時取不到」, no empty snapshot is saved. → Task 7 test `testEmptyHoldingsThrow`, Task 8 test `testFailedFetchKeepsPreviousSnapshot`.
4. **Alert already fired, price stays past the threshold on the next check:** no second notification. → Task 10 test `testFiredAlertDoesNotRepeat`.
5. **Lapsed member with alerts saved:** no notification fires; alerts are still listed. → Task 10 test `testNonMemberNeverFires`.

---

### Task 1: Member gate

**Files:**
- Create: `PocketCore/Sources/PocketCore/Models/MemberFeature.swift`
- Create: `App/Membership/MemberLock.swift`
- Modify: `App/Membership/MemberView.swift` (`MembershipStore`, `Plan.detail`)
- Modify: `App/ETFToGoApp.swift` (read `--demo-member`)
- Modify: `App/ToolsView.swift` (crown badge on member tiles)
- Test: `PocketCore/Tests/PocketCoreTests/MemberFeatureTests.swift`, `Tests/MemberGateTests.swift`

**Interfaces:**
- Produces: `enum MemberFeature: String, CaseIterable, Codable { case overlap, activeTracking, scenarios, goalPlanner, report, backtest, priceAlerts }` with `var title: String` (重疊成分, 主動式追蹤, 多情境試算, 存錢目標反推, 口袋月報年報, 回測, 到價提醒) and `var pitch: String` (one line each, your wording).
- Produces: `MembershipStore.has(_ feature: MemberFeature) -> Bool` (= `isMember || demoMember`), `var demoMember: Bool` set from launch args `--ui-testing` + `--demo-member`.
- Produces: `struct MemberLock<Content: View, Preview: View>: View` — `init(_ feature: MemberFeature, @ViewBuilder content: () -> Content, @ViewBuilder preview: () -> Preview)`. Member → `content`. Non-member → `preview` (dimmed, non-interactive, `.accessibilityHidden(true)`) under a card with crown, 「口袋會員專屬」, `feature.title`, `feature.pitch`, and a button 「看看口袋會員」 pushing `AppRoute.member`. Accessibility id `member-lock-\(feature.rawValue)`.
- Produces: `MemberCrown` small view used as a tile badge.

- [ ] **Step 1: Write failing tests**
  - PocketCore `testEveryFeatureHasTitleAndPitch`: for all cases, `title` and `pitch` non-empty; titles unique.
  - App `testDemoMemberNeedsUITesting`: `MembershipStore.demoMember(from: ["--demo-member"]) == false`; `(["--ui-testing","--demo-member"]) == true`. (Expose `static func demoMember(from args: [String]) -> Bool`.)
  - App `testHasFollowsMembership`: store with `apply([])` and demo off → `has(.backtest) == false`; `apply([MembershipProducts.pocketMonthly])` → `true`.
- [ ] **Step 2: Push, run CI, confirm the new tests fail to compile/fail.** `gh workflow run native-ui.yml --ref claude/pocket-member-features`
- [ ] **Step 3: Implement** the interfaces above. `Plan.pocket.detail` becomes 「成分重疊・回測・目標反推・到價提醒・月報年報・全部皮膚」.
- [ ] **Step 4: CI green** (core + simulator).
- [ ] **Step 5: Commit** `feat(member): MemberFeature gate, MemberLock, --demo-member`

### Task 2: Lock existing overlap and scenarios

**Files:**
- Modify: `App/ResearchViews.swift` (`ExposureView`, overlap tab)
- Modify: `App/ComboViews.swift` (scenario picker in `ComboResultView`)
- Test: `Tests/MemberGateTests.swift`, `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: `MemberLock`, `MembershipStore.has`.
- `ExposureView` tab 1 (重疊成分) → `MemberLock(.overlap)`; preview = a fixed fake overlap list (3 rows, e.g. 台積電 2 檔, 鴻海 2 檔, 聯發科 2 檔). Tab 0 unchanged.
- `ComboResultView`: non-members see 基準 only; selecting 樂觀/保守/壓力測試 shows `MemberLock(.scenarios)` in place of the result. Saved `ComboSettings` are not modified.

- [ ] **Step 1: Failing UI test** `testNonMemberSeesOverlapLock`: launch `--ui-testing --skip-onboarding --open exposure`, tap 「重疊成分」, assert `member-lock-overlap` exists; relaunch with `--demo-member`, assert it does not.
- [ ] **Step 2: CI run, see it fail.**
- [ ] **Step 3: Implement.** Add `exposure` to `AppRoute.launchStack` if not already openable.
- [ ] **Step 4: CI green.**
- [ ] **Step 5: Commit** `feat(member): lock 重疊成分 and non-base scenarios`

### Task 3: 存錢目標反推

**Files:**
- Create: `PocketCore/Sources/PocketCore/Models/GoalPlanner.swift`
- Create: `App/Member/GoalPlannerView.swift`
- Modify: `App/HomeScreens.swift` (`AppRoute.goalPlanner`, route), `App/ToolsView.swift` (tile in 更多工具 with crown)
- Test: `PocketCore/Tests/PocketCoreTests/GoalPlannerTests.swift`

**Interfaces:**
- Produces: `enum GoalPlanner { static func monthlyContribution(target: Double, years: Int, current: Double, annualReturn: Double) -> Double }` — annual % → monthly rate `r = (1 + a/100)^(1/12) − 1`, contributions at month end, `n = years*12`; result `max(0, (target − current·(1+r)^n) · r / ((1+r)^n − 1))`; `r == 0` → `max(0, (target − current)/n)`; `years <= 0` or non-finite input → `0`.
- Produces: `static func scenarios(target:years:current:annualReturn:) -> [(scenario: ComboScenario, annualReturn: Double, monthly: Double)]` for `.optimistic, .base, .conservative` in that order, each using `ComboScenario.rate(annualReturn)` (PocketCore `Models/Combo.swift`: base+3 / base / base−7); a rate ≤ −100 is clamped to −99.

- [ ] **Step 1: Failing tests**
  - `testTenYearsThreeMillionAtSixPercent`: `monthlyContribution(target: 3_000_000, years: 10, current: 0, annualReturn: 6)` ≈ `18464.56` (±0.01).
  - `testExistingMoneyReducesContribution`: same with `current: 500_000` ≈ `12953.35`.
  - `testZeroReturnIsStraightDivision`: `annualReturn: 0` → `25000.0`.
  - `testAlreadyThereIsZero`: `current: 4_000_000` → `0`.
  - `testScenariosUseComboRates`: base 6 → annual returns [9, 6, −1]; monthly amounts strictly increasing in that order.
- [ ] **Step 2: CI run, see them fail.**
- [ ] **Step 3: Implement** core + view: fields 目標金額、年數、目前已有、假設年報酬; result card shows 每月需投入 and the three scenarios; wrapped in `MemberLock(.goalPlanner)` with a fixed preview; disclaimer copy from Global Constraints. `--open goalPlanner` works.
- [ ] **Step 4: CI green.**
- [ ] **Step 5: Commit** `feat(member): 存錢目標反推`

### Task 4: Official history parsers

**Files:**
- Create: `PocketCore/Sources/PocketCore/Sources/OfficialHistory.swift`
- Test: `PocketCore/Tests/PocketCoreTests/OfficialHistoryTests.swift` (fixtures `SharedFixtures/member/official/*`)

**Interfaces:**
- Produces: `struct DailyBar: Codable, Equatable { var date: String /* yyyy-MM-dd */; var close: Double }`
- Produces: `struct DividendEvent: Codable, Equatable { var symbol: String; var exDate: String; var cash: Double }`
- Produces: `struct SplitEvent: Codable, Equatable { var symbol: String; var resumeDate: String; var ratio: Double /* shares after ÷ before; 4 for 0050, 1/7 for 00632R */ }`
- Produces: `enum OfficialHistory` with
  - `static func rocDate(_ s: String) -> String?` — accepts `114/06/18` and `114年01月17日` → `2025-06-18` / `2025-01-17`.
  - `static func twseMonth(_ data: Data) throws -> [DailyBar]` (STOCK_DAY; `[]` when `stat` is the 「沒有符合條件」 message)
  - `static func tpexMonth(_ data: Data) throws -> [DailyBar]` (tradingStock; `[]` on empty `data`)
  - `static func twseDividends(_ data: Data) throws -> [DividendEvent]` (TWT49U; rows with `權/息 == "息"` only; cash = `權值+息值`)
  - `static func tpexDividends(_ data: Data) throws -> [DividendEvent]` (exDailyQ; cash = `現金股利`; trim names; skip rows whose column count ≠ field count)
  - `static func splits(_ data: Data) throws -> [SplitEvent]` (TWTCAU; `x = 停止買賣前收盤價格 ÷ 恢復買賣參考價`; `ratio = x >= 1 ? x.rounded() : 1 / (1/x).rounded()`)
  - `static func suspectedSplits(_ bars: [DailyBar], dividends: [DividendEvent], known: [SplitEvent]) -> [String]` — dates where close changes by more than ×2.5 or below ×0.4 day-over-day, with no dividend that day and no known split → those dates (used to flag 「資料可能未還原」).
  - URL builders: `twseMonthURL(symbol:month: YearMonth) -> URL`, `tpexMonthURL(symbol:month:) -> URL`, `twseDividendsURL(from:to:) -> URL`, `tpexDividendsURL(from:to:) -> URL`, `splitsURL(from:to:) -> URL` (templates in Appendix A).

- [ ] **Step 1: Failing tests**
  - `testRocDates`: `"114/06/18"→"2025-06-18"`, `"114年01月17日"→"2025-01-17"`, `"abc"→nil`.
  - `testTwseMonth`: fixture A → 4 bars; first `DailyBar(date: "2025-06-02", close: 175.90)`; contains `("2025-06-10", 188.65)`.
  - `testTpexMonth`: fixture B → 3 bars; first `("2025-06-02", 25.21)`.
  - `testTwseDividends`: fixture TWT49U → contains `DividendEvent(symbol: "0050", exDate: "2025-01-17", cash: 2.7)` and `("00878","2025-02-20",0.5)`.
  - `testTpexDividends`: fixture exDailyQ → first `("00937B","2025-01-22",0.082)`.
  - `testSplits`: fixture D → 12 events; `0050` resume `2025-06-18` ratio `4`; `00632R` ratio `1.0/7.0` (±1e-9).
  - `testSuspectedSplitFlagged`: bars 100 → 25 next day, no events → that date returned; with a matching `SplitEvent` → `[]`.
- [ ] **Step 2: CI, see fail.** **Step 3: Implement.** **Step 4: CI green.**
- [ ] **Step 5: Commit** `feat(core): official TWSE/TPEx history, dividends and splits parsers`

### Task 5: Backtest engine

**Files:**
- Create: `PocketCore/Sources/PocketCore/Analytics/Backtest.swift`
- Test: `PocketCore/Tests/PocketCoreTests/BacktestTests.swift`

**Interfaces:**
- Consumes: `DailyBar`, `DividendEvent`, `SplitEvent`, `YearMonth`.
- Produces: `struct SymbolHistory { var bars: [DailyBar]; var dividends: [DividendEvent]; var splits: [SplitEvent]; var suspect: Bool }`
- Produces: `struct BacktestInput { var legs: [(symbol: String, weight: Double)]; var monthly: Double; var start: YearMonth; var end: YearMonth; var reinvest: Bool }` (weights sum to 1)
- Produces: `struct BacktestResult { var invested: Double; var endValue: Double; var dividends: Double; var xirr: Double?; var maxDrawdown: Double /* 0…1 */; var curve: [(month: YearMonth, invested: Double, value: Double)]; var notes: [String] }`
- Produces: `enum Backtest { static func run(_ input: BacktestInput, history: [String: SymbolHistory]) -> BacktestResult }` and `enum Finance { static func xirr(_ flows: [(date: Date, amount: Double)]) -> Double? }` (365-day convention; bisection on −0.99…10; nil if no sign change).
- Rules: each month, on that leg's first bar of the month, buy `monthly × weight ÷ close` fractional shares. On a split's `resumeDate`, shares ×= ratio before that day's buy. On a dividend's `exDate`, cash = shares × cash; reinvest → buy at that day's close (next bar if none that day); else add to cash. Month value = Σ shares × last close of the month + cash. A leg with no bars before `start` starts at its first bar month and adds note 「<代號> 於 <yyyy-MM> 上市，之前的月份不投入」. `suspect` legs add note 「<代號> 資料可能未還原，結果僅供參考」. XIRR flows: each contribution negative on its buy date, end value positive on the last bar date.

- [ ] **Step 1: Failing tests** (synthetic histories)
  - `testTwoMonthsNoDividends`: bars `2024-01-02 10`, `2024-01-31 10`, `2024-02-01 20`, `2024-02-29 20`; monthly 1000, 2024-01…2024-02 → invested 2000, endValue 3000, maxDrawdown 0.
  - `testDividendReinvestVersusCash`: same bars + dividend `2024-01-15` cash 1.0 with bar `2024-01-15 10` → reinvest endValue 3200, cash endValue 3100, dividends 100 both.
  - `testSplitDoesNotLookLikeACrash`: bars `2025-06-02 100`, `2025-06-18 25`, `2025-07-01 25`; split `2025-06-18` ratio 4; monthly 1000, 2025-06…2025-07 → endValue 2000, maxDrawdown 0.
  - `testLateListingStartsAtFirstBar`: leg bars start 2024-03; input start 2024-01 → invested counts only from 2024-03; notes contain 「上市」.
  - `testXirrTenPercent`: flows `(2023-01-01, −1000)`, `(2024-01-01, 1100)` → 0.10 ±1e-4.
  - `testMaxDrawdown`: month values 100,120,90,130 → 0.25.
- [ ] **Step 2–4: CI fail → implement → CI green.**
- [ ] **Step 5: Commit** `feat(core): DCA backtest engine with splits, dividends, XIRR`

### Task 6: History client, cache and 回測 screen

**Files:**
- Create: `App/Member/OfficialHistoryClient.swift`, `App/Member/BacktestView.swift`
- Modify: `App/HomeScreens.swift` (`AppRoute.backtest`), `App/ToolsView.swift` (tile with crown)
- Test: `Tests/BacktestClientTests.swift`

**Interfaces:**
- Consumes: Task 4 parsers/URLs, Task 5 `Backtest.run`, `MemberLock(.backtest)`, `PublicHTTP` (existing).
- Produces: `actor OfficialHistoryClient { static let shared; func history(symbol: String, market: String, from: YearMonth, to: YearMonth, progress: @Sendable (Double) -> Void) async throws -> SymbolHistory }`
  - Market from the catalog (`Fund.market`, "TWSE"/"TPEx"). Fugle key present → use existing `ResearchData.history` (adjusted) and mark source 富果; otherwise official path.
  - Cache: `Application Support/history/<symbol>/<yyyy-MM>.json` (bars); past months never refetched; current month refetched if older than 1 day. Dividends/splits cached per calendar year, refetched for the current year if older than 1 day.
  - Throttle: ≥ 2 s between official requests (one shared limiter).
- Screen: pick 1–3 ETFs and weights, 每月投入, 起始 (1／3／5／10 年前), 配息再投入 toggle → progress while downloading (「第一次下載需要幾十秒，離開這頁會停止」) → result card (投入總額、期末市值、累計領息、年化報酬、最大回落) + curve chart + notes + 「過去績效不代表未來」 + data source line. Last inputs persisted with `@AppStorage`.

- [ ] **Step 1: Failing tests**
  - `testCachedPastMonthIsNotRefetched`: with an injected fake fetcher (protocol `HistoryFetching { func get(_ url: URL) async throws -> Data }`), two calls for the same past month → fetcher called once.
  - `testCurrentMonthRefetchedAfterADay`: cache timestamp 25 h old → refetched.
- [ ] **Step 2–4: CI fail → implement → CI green.** `--open backtest` opens the screen.
- [ ] **Step 5: Commit** `feat(member): 回測 with official history cache`

### Task 7: Fund-company holdings parsers

**Files:**
- Create: `PocketCore/Sources/PocketCore/Sources/IssuerHoldings.swift`
- Test: `PocketCore/Tests/PocketCoreTests/IssuerHoldingsTests.swift` (fixtures `SharedFixtures/member/issuers/*`)

**Interfaces:**
- Produces: `enum Issuer: String, CaseIterable, Codable { case yuanta, cathay, fubon, capital, fhtrust, ctbc }` with `displayName` (元大投信, 國泰投信, 富邦投信, 群益投信, 復華投信, 中國信託投信).
- Produces: `enum IssuerDirectory { static func issuer(forFundName name: String) -> Issuer? }` — by name prefix: 元大→yuanta, 國泰→cathay, 富邦→fubon, 群益→capital, 復華→fhtrust, 中信 / 中國信託→ctbc. (No ETFortune fetch: its terms forbid automated download.)
- Produces: `enum IssuerHoldings` parsers, each `throws -> ComponentSnapshot` (existing type; `source` = `displayName`; date `yyyy-MM-dd`; `validate()` must pass; zero stock rows → throw):
  - `yuanta(_ data: Data, symbol: String)` — `FundWeights.StockWeights[] {code,name,weights}`, date `PCF.trandate` (yyyyMMdd)
  - `cathay(_ data: Data, symbol: String, date: String)` — `result[] {stockCode,stockName,weights(string)}`
  - `fubon(_ html: String, symbol: String)` — table rows after the 股票代碼/股票名稱/股數/金額/權重(%) header; date from 「資料日期：yyyy/MM/dd」
  - `capital(_ data: Data, symbol: String)` — `data.stocks[] {stocNo,stocName,weight}`, date `data.pcf.date2`
  - `fhtrust(_ data: Data, symbol: String)` — `result[0].detail[]` where `ftype == "股票"`, `stockid`, `stockname`, weight from `prate_addaccint` ("4.123%"), date `result[0].dDate` (yyyy/MM/dd)
  - `ctbc(_ data: Data, symbol: String)` — `Data.FundAssetsDetail[Code == "STOCK"].Data[] {code_,name_,weights_}`, date `Data.FundAssets[0]["資料日期"]`
  - Code-lookup parsers: `cathayFundCode(_ data: Data, symbol: String) -> String?` (GetETFList), `capitalFundNo(_ data: Data, symbol: String) -> String?` (items), `fhtrustFundID(_ html: String, symbol: String) -> String?` (etf_list page), `ctbcFID(_ data: Data, symbol: String) -> String?` (ETFList).
  - Numbers: strip commas and `%`.

- [ ] **Step 1: Failing tests** (one per parser)
  - `testYuanta`: 0050 fixture → first component `2330` 台積電 58.7; date `2026-11-11`.
  - `testCathay`: 00878 fixture with date `2026-11-13` → first `2891` 中信金 11.26; 3 components.
  - `testCapital`: 00919 → first `2881` 富邦金 16.1341; date `2026-11-13`.
  - `testFhtrust`: 00929 → first `2357` 華碩電腦 4.123; date `2026-11-11`.
  - `testCtbc`: 00934 → first `3293` 鈊象電子 8.10; date `2026-11-13`.
  - `testFubon`: 006208 excerpt → at least 1 component, all weights in (0, 100], date `2026-11-13`.
  - `testEmptyHoldingsThrow`: yuanta JSON with `StockWeights: []` → throws; random JSON `{}` → throws for every parser.
  - `testIssuerByName`: 元大台灣50→yuanta, 國泰永續高股息→cathay, 富邦台50→fubon, 群益台灣精選高息→capital, 復華台灣科技優息→fhtrust, 中信關鍵半導體→ctbc, 統一台灣高息動能→nil.
  - Lookup tests against `E_capital_items_sample.json`, `E_ctbc_ETFList_sample.json` (assert the 00919→`195`, 00934→`E0024` mappings if present in the sample; otherwise assert a code that is present).
- [ ] **Step 2–4: CI fail → implement → CI green.**
- [ ] **Step 5: Commit** `feat(core): six fund-company holdings parsers`

### Task 8: Holdings client chain and snapshot history

**Files:**
- Create: `App/Member/HoldingsClient.swift`
- Modify: `PocketCore/Sources/PocketCore/Models/CoreModels.swift` (`Portfolio.componentHistory: [String: [ComponentSnapshot]]? = nil`)
- Modify: `App/Models.swift` (`saveComponents` also appends history, keep 12 newest by date, drop same-date duplicate)
- Modify: `App/ResearchViews.swift` (`ComponentsContent` and `ExposureView.load` call `HoldingsClient` instead of `Fugle.components` directly)
- Test: `Tests/HoldingsClientTests.swift`

**Interfaces:**
- Consumes: Task 7.
- Produces: `actor HoldingsClient { static let shared; func components(symbol: String, fundName: String) async throws -> ComponentSnapshot }` — order: issuer from `IssuerDirectory` → that issuer's request chain (Appendix A; lookups cached 30 days in `UserDefaults`) → Fugle if a key is saved → throw `AppDataError("這家投信暫不支援")`. At most one network fetch per symbol per Taipei day (return today's stored snapshot otherwise). A parse/HTTP failure throws `AppDataError("暫時取不到，稍後再試")` and reports via the existing load-failure reporter with the issuer name only.
- Produces: `PortfolioStore.componentHistory(for symbol: String) -> [ComponentSnapshot]` (newest first).

- [ ] **Step 1: Failing tests** (inject a fake transport)
  - `testFailedFetchKeepsPreviousSnapshot`: stored snapshot for 0050, transport throws → error thrown, stored snapshot unchanged, history unchanged.
  - `testHistoryKeepsTwelveNewest`: saving 14 snapshots with different dates → 12 kept, newest first; saving the same date twice → one entry.
  - `testOneFetchPerDay`: two calls same day → transport called once.
  - `testUnknownIssuerWithoutKey`: fund name 統一台灣高息動能, no key → throws 「這家投信暫不支援」.
- [ ] **Step 2–4: CI fail → implement → CI green.**
- [ ] **Step 5: Privacy page:** in repo `sonia6891/etftogo`, `privacy/index.html` section 三, add 「各 ETF 發行投信官網公開的持股資料」 and a 到價提醒 sentence (提醒條件只存在 iPhone). Commit and push there (Pages redeploys).
- [ ] **Step 6: Commit** `feat(member): fund-company holdings chain, snapshot history`

### Task 9: 主動式 ETF 追蹤

**Files:**
- Create: `PocketCore/Sources/PocketCore/Analytics/SnapshotDiff.swift`, `App/Member/ActiveTrackingView.swift`
- Modify: `App/HomeScreens.swift` (`AppRoute.activeTracking`), `App/ToolsView.swift` (tile with crown), fund detail 成分 tab (a 「持股變化」 section for active funds)
- Test: `PocketCore/Tests/PocketCoreTests/SnapshotDiffTests.swift`

**Interfaces:**
- Consumes: `componentHistory(for:)`, `Fund.isActive`, `MemberLock(.activeTracking)`.
- Produces: `struct SnapshotChange { var from: String; var to: String; var added: [FundComponent]; var removed: [FundComponent]; var changed: [(component: FundComponent, delta: Double)] }` and `enum SnapshotDiff { static func compare(old: ComponentSnapshot, new: ComponentSnapshot) -> SnapshotChange }` — `changed` = present in both with |Δweight| ≥ 0.01, sorted by |Δ| desc, top 10.
- Screen: list of active ETFs from holdings ∪ favorites; each shows latest date and the change since the previous snapshot; one snapshot only → 「下次更新後就能看到變化」; button 更新 calls `HoldingsClient`.

- [ ] **Step 1: Failing tests**
  - `testDiff`: old {A:10,B:5,C:3}, new {A:12,B:5,D:4} → added [D], removed [C], changed [(A, +2)].
  - `testTinyChangeIgnored`: A 10 → 10.005 → changed empty.
  - `testTopTen`: 15 changed rows → 10, largest |Δ| first.
- [ ] **Step 2–4: CI fail → implement → CI green.**
- [ ] **Step 5: Commit** `feat(member): 主動式 ETF 追蹤`

### Task 10: 到價提醒

**Files:**
- Create: `PocketCore/Sources/PocketCore/Models/PriceAlert.swift`, `App/Member/PriceAlertsView.swift`, `App/Member/PriceAlertMonitor.swift`
- Modify: `PocketCore/.../CoreModels.swift` (`Portfolio.alerts: [PriceAlert]? = nil`), `App/ETFToGoApp.swift` (check on `.active`, register BG task), `project.yml` (Info.plist `BGTaskSchedulerPermittedIdentifiers: [tw.sonia.etftogo.alerts]`, `UIBackgroundModes: [fetch]`), `App/HomeScreens.swift` (`AppRoute.priceAlerts`), `App/ToolsView.swift`, fund detail (「設到價提醒」 button)
- Test: `PocketCore/Tests/PocketCoreTests/PriceAlertTests.swift`

**Interfaces:**
- Produces: `struct PriceAlert: Codable, Identifiable, Equatable { var id = UUID(); var symbol: String; var above: Bool; var price: Double; var enabled = true; var firedAt: Date? = nil }`
- Produces: `enum AlertEngine { static let limit = 20; static func due(_ alerts: [PriceAlert], prices: [String: Double], isMember: Bool) -> [UUID] }` — enabled alerts where `above ? price >= target : price <= target`; `isMember == false` → `[]`.
- Produces: `PriceAlertMonitor.check() async` — refresh quotes for alert symbols via `PortfolioStore.refresh(symbols:)`, call `due`, for each id post a local notification 「<代號> 已到 <價格>」, set `enabled = false`, `firedAt = now`. `scheduleNext()` submits `BGAppRefreshTaskRequest(identifier: "tw.sonia.etftogo.alerts")` with `earliestBeginDate` +1 h when any alert is enabled and the user is a member.
- Screen: list + add (symbol, 高於/低於, price), toggle to re-enable fired alerts, limit 20 with message, copy from Global Constraints; `MemberLock(.priceAlerts)`.

- [ ] **Step 1: Failing tests**
  - `testAboveFiresAtOrOver`: above 100 with 100 → due; with 99.9 → not.
  - `testBelowFires`: below 50 with 49 → due.
  - `testFiredAlertDoesNotRepeat`: alert after firing (`enabled = false`) with price still over → not due.
  - `testNonMemberNeverFires`: `isMember: false` → `[]`.
  - `testMissingPriceSkipped`: no price for symbol → not due.
- [ ] **Step 2–4: CI fail → implement → CI green** (Release compile step too, for the new Info.plist keys).
- [ ] **Step 5: Commit** `feat(member): 到價提醒 (foreground + background refresh)`

### Task 11: 口袋月報／年報

**Files:**
- Create: `PocketCore/Sources/PocketCore/Analytics/PocketReport.swift`, `App/Member/PocketReportView.swift`
- Modify: `PocketCore/.../GameState.swift` (`xpByMonth: [String: Int] = [:]`, keyed `yyyy-MM`; add to it wherever XP is awarded), `App/HomeScreens.swift` (`AppRoute.report`), `App/ToolsView.swift`, lobby (one-time 「上個月的口袋月報出爐了」 notice per new month, `@AppStorage("reportSeenMonth")`)
- Test: `PocketCore/Tests/PocketCoreTests/PocketReportTests.swift`

**Interfaces:**
- Produces: `enum ReportPeriod: Equatable { case month(YearMonth), year(Int), yearToDate(Int) }`
- Produces: `struct ReportCard: Equatable { var title: String; var dividends: Double; var dcaMonths: Int; var reconciles: Int; var newDexCards: Int; var level: Int; var xpEarned: Int?; var notes: [String] }`
- Produces: `enum PocketReport { static func make(_ period: ReportPeriod, portfolio: Portfolio, now: Date) -> ReportCard }` — dividends = paid `Dividend.amount` with `date` in period; dcaMonths = `game.dcaMonths` in period; reconciles = count of `game` reward keys `reconciled|yyyy-MM` in period; newDexCards = `game.collected` dates in period; level from `GameRules.level(xp:)`; xpEarned = sum of `xpByMonth` in period, `nil` when no month in the period has an entry (then the card omits it).
- Screen: tabs 月報／年報／今年到目前; card drawn with skin kit; never shows market value or returns; toggle 「顯示領息金額」 (default on); 「分享」 renders the card with `ImageRenderer` → `ShareLink` (image only, made on device). `MemberLock(.report)`.

- [ ] **Step 1: Failing tests** (fixture portfolio built in test)
  - `testMonthTotals`: dividends 2026-10-05 300 paid, 2026-10-20 200 paid, 2026-11-01 999 paid, 2026-10-25 50 pending → `.month(2026-10)` dividends 500.
  - `testYearCountsDcaAndReconciles`: dcaMonths {2025-12, 2026-01, 2026-03}, keys `reconciled|2026-01`, `reconciled|2026-03` → `.year(2026)` dcaMonths 2, reconciles 2.
  - `testXpOmittedWithoutLog`: empty `xpByMonth` → `xpEarned == nil`.
- [ ] **Step 2–4: CI fail → implement → CI green.**
- [ ] **Step 5: Commit** `feat(member): 口袋月報／年報 with share image`

### Task 12: Screenshots and UI coverage

**Files:**
- Modify: `.github/workflows/native-ui.yml` (feature-screen step), `UITests/ETFToGoUITests.swift`

- [ ] **Step 1:** Feature-screen loop: add `goalPlanner backtest priceAlerts activeTracking report exposure` launched with `--demo-member`, plus `backtest` and `report` without it saved as `screen-<id>-locked.png`.
- [ ] **Step 2:** UI test `testEveryMemberFeatureOpens`: with `--demo-member`, each `--open` route shows its screen and no `member-lock-*`; without it, each shows `member-lock-<feature>`.
- [ ] **Step 3:** CI green; download `ETFToGo-screens` and check every new screenshot renders (no blank screen, lock card visible on the locked ones).
- [ ] **Step 4: Commit** `test(member): screenshots and UI coverage for member features`

---

## Appendix A: Endpoints (verified live 2026-11-13; samples in `SharedFixtures/member/`)

Dates from TWSE/TPEx are ROC (`114/06/18`, `114年01月17日`); request parameters are AD. Numbers are strings with commas.

| Use | Request | Notes |
|---|---|---|
| TWSE month bars | `GET https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY?date=YYYYMM01&stockNo=<code>&response=json` | `data[][6]` 收盤價, `data[][0]` date. Unadjusted. Throttle 1 req / 2 s. |
| TPEx month bars | `GET https://www.tpex.org.tw/www/zh-tw/afterTrading/tradingStock?code=<code>&date=YYYY/MM/01&response=json` | `tables[0].data[][6]` 收盤; unknown code → empty `data` with `stat:"ok"`. |
| TWSE dividends | `GET https://www.twse.com.tw/rwd/zh/exRight/TWT49U?startDate=YYYYMMDD&endDate=YYYYMMDD&response=json` | all securities; `資料日期`, `股票代號`, `權值+息值`, `權/息`. |
| TPEx dividends | `GET https://www.tpex.org.tw/www/zh-tw/bulletin/exDailyQ?startDate=YYYY/MM/DD&endDate=YYYY/MM/DD&response=json` | `除權息日期`, `代號`, `現金股利` (idx 13). Validate row width. |
| ETF splits | `GET https://www.twse.com.tw/rwd/zh/split/TWTCAU?startDate=20150101&endDate=YYYYMMDD&response=json` | ratio = 停止買賣前收盤價格 ÷ 恢復買賣參考價. No TPEx equivalent. |
| 元大 | `GET https://etfapi.yuantaetfs.com/ectranslation/api/bridge?APIType=ETFAPI&FuncId=PCF/Daily&ticker=<code>` | no lookup. |
| 國泰 | lookup `GET https://cwapi.cathaysite.com.tw/api/ETF/GetETFList?Keyword=<code>` → `fundCode`; date `GET .../api/ETF/GetETFAssets?FundCode=<fc>` → `preDate`; holdings `GET .../api/ETF/GetETFDetailStockList?FundCode=<fc>&SearchDate=YYYY-MM-DD` | Akamai rejects empty/curl UA; default iOS CFNetwork UA works. |
| 富邦 | `GET https://websys.fsit.com.tw/FubonETF/Fund/Assets.aspx?stkId=<code>` | HTML table. |
| 群益 | lookup `POST https://www.capitalfund.com.tw/CFWeb/api/etf/items` → `fundNo`; holdings `POST .../CFWeb/api/etf/buyback` body `{"fundId":"<no>","date":null}` | JSON body, `Content-Type: application/json`. |
| 復華 | lookup `GET https://www.fhtrust.com.tw/ETF/etf_list` (HTML, ETF01–ETF27); holdings `GET https://www.fhtrust.com.tw/api/assets?fundID=<id>&qDate=YYYY/MM/DD` | slashes required in qDate; try today then previous days (max 5) until rows. |
| 中信 | token `POST https://www.ctbcinvestments.com.tw/API/home/AuthToken?token=www.ctbcinvestments.com` body `{"token":"www.ctbcinvestments.com"}`; lookup `POST .../API/etf/ETFList?token=<enc>` body `{token,"IsWithETF":"Y"}` → FID; holdings `POST .../API/etf/ETFHoldingWeight?token=<enc>` body `{token,"FID":"<fid>","StartDate":"YYYY/MM/DD"}` | token must be URL-encoded; passing the ETF code instead of FID returns empty arrays (treat as failure). |

Do not use `https://www.twse.com.tw/zh/ETFortune/*` (terms forbid automated download).
