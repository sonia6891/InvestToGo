# Quick DCA and Monthly Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Logging this month's DCA takes two taps (「記一筆」 then 「記好了」), and the monthly debit-day reminder names the amount and the ETF, stops once the month is logged, and opens that same sheet when tapped.

**Architecture:** Pure rules live in PocketCore and are tested on Linux: the saved preset (`Portfolio.quickDCA`), the sheet's defaults and checks, "is this month's DCA still in the records", and the 12-month reminder schedule. The app adds a half-height `QuickDCASheet` that saves through `PortfolioStore.applyTrade(.buy, …, logBuy: true)`, a lobby button in the 「本月定投一次」 row, a reminder sync that the root view re-runs from the current records, and one app-wide notification delegate that routes a tapped reminder to the sheet.

**Tech Stack:** SwiftUI (iOS 18), UserNotifications, XCTest, XCUITest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-habit-loop-and-polish-design.md` (Traditional Chinese, binding). This plan is delivery item §12.1 and implements §3, §4, and rulings §10.2, §10.3, §10.4, §10.9 and §10.10.

## Global Constraints

- All copy is Traditional Chinese (Taiwan usage). Say 「外觀主題」, never 「皮膚」 (§9).
- No new third-party packages (§9).
- Network requests still carry only ETF codes and dates. Notifications never use the network (§9).
- Reduce Motion, Low Power Mode and `--ui-testing` follow the living-lobby rules. Under `--ui-testing`, motion jumps to its final state and nothing ambient runs (§9).
- Anti-goals (§1): no one-tap save without a chance to see the entry, and every quick entry stays editable and deletable through the existing trade log. Notifications never show market value, gains or holding amounts. The planned monthly amount is the only amount allowed in a notification, and the reminder center can turn it off (§10.9). Never celebrate price moves. Never show an unreachable 「即將推出」 item (`Upcoming.visible`).
- Record a buy only with `PortfolioStore.applyTrade(.buy, …, logBuy: true)`. Never use `save(_:logBuy:)`, which adds a second holding (§3.2). Note that `applyTrade`'s `logBuy` defaults to `false`, so the quick save must pass `true`.
- `Portfolio.quickDCA` is a purely additive optional field. Old records and old backups decode it as nil, and there is no migration step (§10.2).
- A repeat entry in the same month is allowed and earns no second monthly DCA experience. That rule already exists in `GameState.logBuy`, so keep it unchanged (§3.3).
- Notifications, task ticks (and, in a later plan, the widget) are always derived from the current records and recomputed on every save and every return to the foreground. Deleting this month's only DCA puts this month's reminder back if its time has not passed, and the quest unticks (§10.4).
- Reminder text is rescheduled for the next 12 months whenever the defaults (ETF, amount), the reminder settings, or the foreground state change (§10.3).
- The old repeating ids `dca-reminder` and `dca-reminder-eve` are removed, and the new ones are scheduled, at launch no matter where the reminder was first turned on (§10.10).
- Months and the reminder's day and time are computed in Taipei time (`GameRules.taipei`).
- Exact copy, verbatim:
  - Lobby button 「記一筆」; save button 「記好了」.
  - Share hint 「以 11/20 收盤價估算，可改成實際成交股數」, with the date taken from the quote's day as M/d.
  - Unknown code 「找不到這檔 ETF」.
  - Reminder title 「今天扣款日」, body 「每月 5,000 元・0050，記一筆讓連續定投接下去」.
  - Eve-of reminder body 「明天扣款日，帳戶記得留 5,000 元」.
  - Reminder-center toggle 「通知顯示金額」. With it off, the body reads 「記得確認定期定額」.
- Accessibility identifiers: `lobby-quick-dca`, `quick-dca-save` (§3), plus `quick-dca-symbol`, `quick-dca-amount`, `quick-dca-shares`, `quick-dca-broker`, `quick-dca-date`, `quick-dca-error`, `reminder-dca-show-amount`. Every existing identifier keeps its name.
- Commits: stage named paths only. Never use `git add -A`; an untracked, locally ignored `marketing/` folder belongs to other work.
- Before Task 1: the working tree carries uncommitted 「皮膚 → 外觀主題」 copy edits in `App/Game/LevelUpView.swift`, `App/Membership/MemberView.swift`, `App/Skins/SkinCarousel.swift`, `App/ToolsView.swift`, `PocketCore/Sources/PocketCore/Game/Achievements.swift`, `Tests/StoreDemoTests.swift` and `UITests/ETFToGoUITests.swift`. The controller commits or stashes them first. A task that stages one of those files would otherwise carry them along.
- Verification is CI only; there is no local Swift toolchain. Every task ends with these steps:
  1. `git add <named paths>` and `git commit`.
  2. `git push origin <branch>`, where the branch is the controller's working branch cut from `claude/living-lobby`.
  3. `gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>`.
  4. The jobs `core`, `simulator` and `skin-matrix` are green.

  The tracked `ETFToGo.xcodeproj` is regenerated by `xcodegen generate` in CI, so new files under `App/` and `Tests/` need no project edit.

## Review Focus

1. **iOS keeps at most 64 pending notifications.** DCA reminders now take up to 24 (12 months, each with an eve-of reminder), while 配息提醒 schedules up to 60. Both features must keep working, so the dividend cap drops to 40 (Task 5 test `testDividendReminderCapLeavesRoomForDCA`).
2. **A double tap on 「記好了」.** It must log one buy, not two (Task 3: the button disables while saving; UI test `testQuickDCAFromLobby` asserts one new 買進 trade).
3. **A monthly amount below one share's price** (for example 50 元 for 0050). The share count stays empty and 「記好了」 stays disabled until the person types shares (Task 1 test `testEstimatedShares`).
4. **Deleting this month's only DCA in 交易紀錄.** The quest unticks, 「記一筆」 returns, and this month's reminder comes back if its time is still ahead (Task 1 test `testDCALoggedNeedsABuyStillInTheRecords`; Task 4 test `testUnloggedMonthIsScheduledAgain`).
5. **A phone set to a time zone other than Taipei.** Months and fire times are still Taipei's (Task 4 tests use `GameRules.taipei` dates and assert absolute instants).

---

### Task 1: Quick-DCA rules in PocketCore

**Files:**
- Create: `PocketCore/Sources/PocketCore/Game/QuickDCA.swift`
- Modify: `PocketCore/Sources/PocketCore/Models/CoreModels.swift`. Add `Portfolio.quickDCA`, and in `decodeBackup` drop an invalid preset (set it to nil) rather than throwing.
- Create test: `PocketCore/Tests/PocketCoreTests/QuickDCATests.swift`

**Interfaces:**
- Produces:
  - `struct QuickDCAPreset: Codable, Equatable { var symbol: String; var amount: Int; var broker: String; var isValid: Bool }`. It is valid when `DataChecks.code(symbol)`, `1...1_000_000_000_000 ~= amount` and `broker.count <= 120`.
  - `Portfolio.quickDCA: QuickDCAPreset?` (default nil; the synthesized decoder reads it with `decodeIfPresent`).
  - `struct QuickDCADefaults: Equatable { var symbol: String?; var amount: Int?; var broker: String }`.
  - `enum QuickDCAProblem: Equatable { case unknownFund, invalidAmount, invalidShares; var message: String? }`. Only `unknownFund` has a message: 「找不到這檔 ETF」.
  - `enum QuickDCA` with:
    - `static func defaults(preset: QuickDCAPreset?, onboardingSymbol: String?, onboardingMonthly: Int?, portfolio: Portfolio) -> QuickDCADefaults`.
      - symbol: `preset?.symbol`, else `onboardingSymbol`, else the symbol of the latest-dated `.buy` trade whose symbol is still in `portfolio.holdings`, else nil.
      - amount: `preset?.amount`, else `onboardingMonthly` when it is above 0, else nil.
      - broker: `preset?.broker ?? ""`.
    - `static func estimatedShares(amount: Int?, close: Double?) -> Int?`. Returns `floor(amount / close)`; nil when either input is missing, `close <= 0`, or the result is below 1.
    - `static func closeNote(day: String) -> String?`. `"2026-11-20"` gives 「以 11/20 收盤價估算，可改成實際成交股數」; anything that is not a `DataChecks.date` gives nil.
    - `static func problem(known: Bool, shares: Int?, amount: Int?) -> QuickDCAProblem?`. Checks in this order: `!known` → `.unknownFund`; amount nil or outside `1...1e12` → `.invalidAmount`; shares nil or outside `1...10_000_000_000` → `.invalidShares`; otherwise nil.
    - `static func amountText(_ amount: Int) -> String`. Grouped with `Locale(identifier: "zh_Hant_TW")` so that Linux and iOS agree.
  - `extension Portfolio { func hasBuy(in month: YearMonth) -> Bool }`: some `trades` entry has `action == .buy` and `YearMonth(date) == month`.
  - `extension Portfolio { func dcaLogged(in month: YearMonth) -> Bool }`: `(game?.dcaMonths.contains(month) ?? false) && hasBuy(in: month)`. This is the §4 「本月已記到定投」, derived from the records (§10.4).
  - `extension GameState { func isDone(_ quest: Quest, in month: YearMonth, records: Portfolio) -> Bool }`: `isDone(quest, in: month)` and, for `quest.trigger == .dcaLogged` only, also `records.hasBuy(in: month)`.

- [ ] **Step 1: Write `QuickDCATests`**

```swift
func testDefaultsOrder() {
    // preset {00878, 3000, "國泰"} → (00878, 3000, "國泰")
    // no preset, onboarding ("006208", 5000) → ("006208", 5000, "")
    // neither; holdings 0050 and 00878, buys 0050 on 2026-10-05 and 00878 on 2026-11-05 → ("00878", nil, "")
    // neither; the latest buy's code was sold off (not in holdings) → the latest buy of a held code
    // onboardingMonthly 0 → amount nil
}
func testEstimatedShares() {
    XCTAssertEqual(QuickDCA.estimatedShares(amount: 5000, close: 109), 45)
    XCTAssertEqual(QuickDCA.estimatedShares(amount: 5000, close: 100), 50)
    XCTAssertNil(QuickDCA.estimatedShares(amount: 50, close: 109))   // below one share
    XCTAssertNil(QuickDCA.estimatedShares(amount: 5000, close: nil))
    XCTAssertNil(QuickDCA.estimatedShares(amount: 5000, close: 0))
    XCTAssertNil(QuickDCA.estimatedShares(amount: nil, close: 109))
}
func testCloseNote() {
    XCTAssertEqual(QuickDCA.closeNote(day: "2026-11-20"), "以 11/20 收盤價估算，可改成實際成交股數")
    XCTAssertEqual(QuickDCA.closeNote(day: "2026-01-05"), "以 1/5 收盤價估算，可改成實際成交股數")
    XCTAssertNil(QuickDCA.closeNote(day: ""))
}
func testProblemOrder() {
    XCTAssertEqual(QuickDCA.problem(known: false, shares: 45, amount: 5000), .unknownFund)
    XCTAssertEqual(QuickDCAProblem.unknownFund.message, "找不到這檔 ETF")
    XCTAssertEqual(QuickDCA.problem(known: true, shares: 45, amount: 0), .invalidAmount)
    XCTAssertEqual(QuickDCA.problem(known: true, shares: nil, amount: 5000), .invalidShares)
    XCTAssertEqual(QuickDCA.problem(known: true, shares: 0, amount: 5000), .invalidShares)
    XCTAssertNil(QuickDCA.problem(known: true, shares: 45, amount: 5000))
    XCTAssertNil(QuickDCAProblem.invalidShares.message)
}
func testAmountText() { XCTAssertEqual(QuickDCA.amountText(5000), "5,000"); XCTAssertEqual(QuickDCA.amountText(12000), "12,000"); XCTAssertEqual(QuickDCA.amountText(800), "800") }
func testDCALoggedNeedsABuyStillInTheRecords() {
    // game.dcaMonths ∋ 2026-11, questsDone["2026-11"] = ["dcaLogged"], a .buy trade on 2026-11-06 →
    //   dcaLogged(in: 2026-11) and isDone(Quests.dcaLogged, in: 2026-11, records:) are true
    // the trade removed → both false; isDone(Quests.dcaLogged, in:) (records-free) is still true
    // a .buy dated 2026-11 but dcaMonths without 2026-11 → dcaLogged false, hasBuy true
    // Quests.dividendsViewed done in questsDone → isDone(…, records:) true with no trades at all
}
func testOldBackupHasNoPreset() throws {
    // a Portfolio JSON with no "quickDCA" key → decodeBackup succeeds, quickDCA == nil
}
func testInvalidPresetIsDroppedNotFatal() throws {
    // quickDCA {"symbol":"bad code!","amount":5000,"broker":""} → decodeBackup succeeds, quickDCA == nil, holdings kept
    // a valid preset round-trips through JSONEncoder → decodeBackup unchanged
}
```

- [ ] **Step 2: Implement `QuickDCA.swift` and the `Portfolio.quickDCA` field per Interfaces.** `decodeBackup` already decodes into `let value`. Make it `var`, and set `value.quickDCA = nil` when `value.quickDCA?.isValid == false`.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add PocketCore/Sources/PocketCore/Game/QuickDCA.swift PocketCore/Sources/PocketCore/Models/CoreModels.swift PocketCore/Tests/PocketCoreTests/QuickDCATests.swift
git commit -m "feat(core): quick DCA preset, defaults and the records-derived DCA month"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: `core` green (QuickDCATests pass), `simulator` and `skin-matrix` green.

---

### Task 2: Saving a quick DCA through the store

**Files:**
- Modify: `App/Models.swift`.
  - `applyTrade` gains `quickDCA: QuickDCAPreset? = nil`. When it is non-nil, it sets `next.quickDCA` in the same write.
  - `importBackup` carries `next.quickDCA = incoming.quickDCA ?? next.quickDCA`.
- Create: `App/Lobby/QuickDCADraft.swift` (the store extension below)
- Create test: `Tests/QuickDCAStoreTests.swift`

**Interfaces:**
- Consumes (Task 1): `QuickDCA.defaults`, `estimatedShares`, `closeNote`, `problem`, `QuickDCAPreset`.
- Produces:
  - `struct QuickDCADraft: Equatable { var symbol: String; var amount: Int?; var shares: Int?; var date: Date; var broker: String; var closeNote: String? }`.
  - `extension PortfolioStore { func quickDCADraft(now: Date = Date(), defaults: UserDefaults = .standard) -> QuickDCADraft }`.
    - The defaults come from `QuickDCA.defaults(preset: data.quickDCA, onboardingSymbol: defaults.string(forKey: Onboarding.symbolKey), onboardingMonthly: Onboarding.monthlyDefault(defaults), portfolio: data)`.
    - `date` is `now`.
    - `shares` is `QuickDCA.estimatedShares(amount:, close: quote(symbol)?.price)`.
    - `closeNote` is `quote(symbol).flatMap { QuickDCA.closeNote(day: $0.date) }`, and nil when `shares` is nil.
  - `extension PortfolioStore { func quickDCAKnows(_ symbol: String) -> Bool }`: `funds.contains { $0.id == symbol } || data.holdings.contains { $0.symbol == symbol }`.
  - `extension PortfolioStore { func logQuickDCA(_ draft: QuickDCADraft, now: Date = Date()) throws }`.
    - Throws `AppDataError(QuickDCAProblem.unknownFund.message!)` when the code is unknown, and `AppDataError("請填寫股數與成交金額。")` for the other problems.
    - Otherwise calls `applyTrade(.buy, symbol:, date: draft.date, shares: Double(shares), amount: Double(amount), broker: draft.broker.trimmed, logBuy: true, now: now, quickDCA: QuickDCAPreset(symbol:, amount:, broker:))`.

- [ ] **Step 1: Write `QuickDCAStoreTests`** (temporary `PortfolioStore(url:)`, a `UserDefaults(suiteName:)` that each test clears)

```swift
func testDraftFromPresetOnboardingOrLatestHolding()    // the three cases of QuickDCATests.testDefaultsOrder, through the store and a defaults suite
func testDraftEstimatesWholeSharesFromTheQuote() {
    // data.quotes["0050"] = Quote(symbol: "0050", price: 100, date: "2026-11-20", fetchedAt: now, currency: "TWD") (newer than the bundled close)
    // onboarding monthly 5000 → shares 50, closeNote "以 11/20 收盤價估算，可改成實際成交股數"
    // monthly 50 → shares nil, closeNote nil
}
func testQuickDCAMergesIntoTheHoldingAndPays() throws {
    // holding 0050, 1000 shares, broker ""; game non-newbie (dcaMonths = [last month]), habit .dca
    // logQuickDCA(symbol 0050, amount 5000, shares 50, broker "")
    // → holdings.count == 1, shares == 1050; trades.last action .buy, amount 5000, shares 50
    // → game.dcaMonths ∋ YearMonth(now); xp grew by 100 + 40 (monthly DCA + 本月定投一次)
    // → data.quickDCA == QuickDCAPreset(symbol: "0050", amount: 5000, broker: "")
}
func testSecondQuickDCAThisMonthEarnsNothingMore() throws  // second log → one more .buy trade, xp unchanged
func testUnknownCodeIsRefused() {
    // "9999" in neither funds nor holdings → throws with localizedDescription "找不到這檔 ETF"; data unchanged (trades count, quickDCA nil)
}
func testBackupCarriesThePreset() throws               // export → importBackup into a fresh store → quickDCA equal
func testOldBackupStillRestores() throws               // importBackup of a backup JSON with no quickDCA key → succeeds, holdings imported, quickDCA nil
```

- [ ] **Step 2: Implement per Interfaces.**

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Models.swift App/Lobby/QuickDCADraft.swift Tests/QuickDCAStoreTests.swift
git commit -m "feat(store): quick DCA draft and save through applyTrade, kept in backups"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green.

---

### Task 3: 「記一筆」 in the lobby and the quick-DCA sheet

**Files:**
- Create: `App/Lobby/QuickDCASheet.swift`
- Modify: `App/Lobby/LobbyView.swift` (button in the quest row, records-derived ticks, the sheet, replay after it closes)
- Modify: `PocketCore/Sources/PocketCore/Game/LobbyReplay.swift`: `LobbySnapshot.of(_ game: GameState, records: Portfolio, now: Date)` uses `game.isDone(_:in:records:)`.
- Modify: `PocketCore/Tests/PocketCoreTests/LobbyReplayTests.swift`. `testSnapshotOfGame` passes `records:`, and add `testSnapshotUnticksADeletedDCA`.
- Modify: `App/Lobby/DemoArguments.swift`: `--demo-unlogged`.
- Modify: `UITests/ETFToGoUITests.swift` (new tests below)
- Modify: `.github/workflows/native-ui.yml`. In the "Capture the lobby and every feature screen" step, add `screen-quick-dca.png`, launched with `--ui-testing --skip-onboarding --demo-streak 3 --demo-unlogged --demo-held -onboarding.monthly 5000 --open quickDCA`. The `--open quickDCA` launch arrives in Task 6. Until then this shot shows the lobby, which is acceptable for this task's CI run.

**Interfaces:**
- Consumes: Task 1 `isDone(_:in:records:)`, `QuickDCAProblem`; Task 2 `quickDCADraft`, `quickDCAKnows`, `logQuickDCA`.
- Produces:
  - `struct QuickDCASheet: View { init(onDone: @escaping () -> Void) }`.
    - It is a half-height sheet: `.presentationDetents([.medium, .large])`, title 「記一筆定投」.
    - Fields, all editable: ETF code (`quick-dca-symbol`), 金額 (`quick-dca-amount`), 日期 (`quick-dca-date`, a DatePicker limited to `...Date()`), 股數 (`quick-dca-shares`) with the `closeNote` under it, and 券商（選填） (`quick-dca-broker`).
    - Shares re-estimate when the code or amount changes, until the person edits shares themselves.
    - An unknown code shows 「找不到這檔 ETF」 (`quick-dca-error`).
    - 「記好了」 (`quick-dca-save`) is disabled while `QuickDCA.problem(…) != nil` or while a save is under way.
    - A save error goes to `store.message`. Success plays `ConfirmFeedback.confirm(skin)` and calls `onDone`.
  - `DemoArguments` `--demo-unlogged`: with `--demo-streak n`, the n months end at last month, so this month is still to log.
  - `LobbyView` state `quickDCA: Bool` presents the sheet.
    - `arrive(lead:)` also guards `!quickDCA`. The sheet's `onDismiss` calls `arrive(lead: 0.15)`, so the tick, coins, +XP and bar replay after the sheet has gone (§3.2) and never under it.
- Lobby button rule: the 「本月定投一次」 row (`quest.trigger == .dcaLogged`) shows 「記一筆」 (`lobby-quick-dca`, `PressableStyle`) at its trailing edge when the quest is not done by `isDone(_:in:records:)` and `!store.recordsLocked`. Once it is done the button is gone and the row keeps its tick (§3.1, §3.3). Members and non-members alike.
- The quest card's ticks and the `LobbySnapshot` both use `isDone(_:in:records: store.data)`.

- [ ] **Step 1: Write the failing tests**

```swift
// LobbyReplayTests
func testSnapshotUnticksADeletedDCA()  // questsDone this month ∋ dcaLogged, no .buy trade this month → snapshot.quests lacks "dcaLogged"

// ETFToGoUITests
func testQuickDCAFromLobby() {
    // launch ["--demo-streak", "3", "--demo-unlogged", "--demo-held", "-onboarding.monthly", "5000"]
    // hero label "連續定投 3 個月" exists; tap lobby-quick-dca
    // quick-dca-symbol value "0050"; quick-dca-amount value "5000"; quick-dca-shares value is a whole number > 0
    // a static text BEGINSWITH "以 " and ENDSWITH "收盤價估算，可改成實際成交股數" exists
    // double-tap quick-dca-save → the sheet closes; lobby-quick-dca no longer exists (wait 5 s)
    // hero label "連續定投 4 個月" exists
    // open 口袋 › 交易紀錄 (AppRoute.trades, TradeLogSection): exactly two rows read 「買進」:
    // the --demo-held seed's and one quick entry, so the double tap logged once
}
func testQuickDCARefusesUnknownCode() {
    // same launch; tap lobby-quick-dca; clear quick-dca-symbol, type "9999"
    // static text "找不到這檔 ETF" exists; quick-dca-save.isEnabled == false
}
```

- [ ] **Step 2: Implement `QuickDCASheet`, the lobby button, the records-derived ticks, `--demo-unlogged`, and the screenshot line.** Find the 交易紀錄 route in `App/PortfolioViews.swift` (`AppRoute.trades`) for the UI test's last check.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Lobby/QuickDCASheet.swift App/Lobby/LobbyView.swift App/Lobby/DemoArguments.swift PocketCore/Sources/PocketCore/Game/LobbyReplay.swift PocketCore/Tests/PocketCoreTests/LobbyReplayTests.swift UITests/ETFToGoUITests.swift .github/workflows/native-ui.yml
git commit -m "feat(lobby): 記一筆 logs this month's DCA from a prefilled sheet"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. The lobby shots in `skin-matrix` now show 「記一筆」 in the quest card. Check that it fits in all four skins.

---

### Task 4: The 12-month reminder schedule in PocketCore

**Files:**
- Create: `PocketCore/Sources/PocketCore/Game/DCAReminderPlan.swift`
- Create test: `PocketCore/Tests/PocketCoreTests/DCAReminderPlanTests.swift`

**Interfaces:**
- Consumes: Task 1 `QuickDCA.amountText`.
- Produces:
  - `struct DCAReminderInputs: Equatable { var day: Int; var minutes: Int; var dayBefore: Bool; var showAmount: Bool; var amount: Int?; var symbol: String?; var month: String; var loggedThisMonth: Bool }`. Here `month` is `YearMonth(now).key`, which makes a new month a new task id.
  - `struct DCAReminderRequest: Equatable { var id: String; var fire: Date; var title: String; var body: String; var userInfo: [String: String] }`. `userInfo` is always `["route": "quickDCA"]`.
  - `enum DCAReminderPlan { static let prefix = "dca-reminder"; static let legacyIDs = ["dca-reminder", "dca-reminder-eve"]; static func requests(_ inputs: DCAReminderInputs, now: Date, calendar: Calendar = GameRules.taipei) -> [DCAReminderRequest] }`.

The schedule rule: `start` is the current month, or the next month when the current month is logged or its debit-day time is not after `now`. Twelve months follow from `start`. Each month gets a day reminder `dca-reminder-YYYY-MM` at `day`, `minutes`. With `dayBefore`, it also gets an eve-of reminder `dca-reminder-eve-YYYY-MM` at `day − 1`, same time. Reminders whose fire time is not after `now` are left out. Output is sorted by `fire`.

Text rules (exact):

| case | day title | day body | eve title | eve body |
|---|---|---|---|---|
| amount and symbol known, `showAmount` | 今天扣款日 | 每月 5,000 元・0050，記一筆讓連續定投接下去 | 定期定額提醒 | 明天扣款日，帳戶記得留 5,000 元 |
| amount and symbol known, `!showAmount` | 今天扣款日 | 記得確認定期定額 | 定期定額提醒 | 明天扣款日，記得確認定期定額 |
| amount or symbol missing (the original wording) | 定期定額提醒 | 今天是每月 6 日的扣款日，記得確認定期定額。 | 定期定額提醒 | 明天是每月 6 日的扣款日。 |

- [ ] **Step 1: Write `DCAReminderPlanTests`** (dates built in `GameRules.taipei`; inputs day 6, minutes 540, dayBefore true, showAmount true, amount 5000, symbol "0050")

```swift
func testAfterThisMonthsDebitStartsNextMonth() {
    // now 2026-11-21 10:00 → 24 requests; first id "dca-reminder-eve-2026-12" at 2026-12-05 09:00 +0800,
    // then "dca-reminder-2026-12" at 2026-12-06 09:00 +0800; last "dca-reminder-2027-11"
}
func testBeforeThisMonthsDebitIncludesThisMonth() {
    // now 2026-11-03 08:00 → 24 requests from "dca-reminder-eve-2026-11" (2026-11-05 09:00) to "dca-reminder-2027-10"
}
func testLoggedThisMonthSkipsIt() {
    // now 2026-11-03 08:00, loggedThisMonth true → first "dca-reminder-eve-2026-12", last "dca-reminder-2027-11", 24 requests
}
func testUnloggedMonthIsScheduledAgain() {
    // the same inputs with loggedThisMonth flipped back to false → "dca-reminder-2026-11" is back (deleting the only DCA)
}
func testEvePassedDayAhead() {
    // now 2026-11-05 10:00 → "dca-reminder-2026-11" first, no "dca-reminder-eve-2026-11"; 23 requests; months 2026-11…2027-10
}
func testNoDayBefore()        // dayBefore false, now 2026-11-21 → 12 requests, none with "-eve-"
func testDayThreeEveIsTheSecond() // day 3 → eve of 2026-12 fires 2026-12-02 09:00 +0800
func testTexts()              // the three table rows above, exact strings; every request's userInfo == ["route": "quickDCA"]
func testIdsAreUnique()       // Set(ids).count == ids.count
```

- [ ] **Step 2: Implement `DCAReminderPlan.requests`.**

- [ ] **Step 3: Commit, push, run CI**

```bash
git add PocketCore/Sources/PocketCore/Game/DCAReminderPlan.swift PocketCore/Tests/PocketCoreTests/DCAReminderPlanTests.swift
git commit -m "feat(core): twelve months of one-shot DCA reminders, skipped once logged"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: `core` green; the other jobs green.

---

### Task 5: Reminder sync in the app

**Files:**
- Modify: `App/Onboarding/OnboardingFlow.swift`.
  - Rewrite `DCAReminders`. Remove the repeating `schedule(day:minutes:dayBefore:)` and `ids`; keep `summary`, `time` and `minutes`.
  - `finish(confirm:)` no longer schedules anything; it only saves the keys.
  - Add `DCAReminders.showAmountKey` to `Onboarding.keys`, so that `--reset` clears it.
- Modify: `App/ToolsView.swift`.
  - `ReminderCenterView`: add the toggle 「通知顯示金額」 (`reminder-dca-show-amount`, `@AppStorage(DCAReminders.showAmountKey)`, default true, disabled while the reminder is off). Picker, time, eve and toggle changes only write their keys; `reschedule()` goes away.
  - `DividendReminders`: `static let limit = 40` replaces the literal 60.
- Modify: `App/ETFToGoApp.swift`.
  - `RootView` reads the seven inputs with `@AppStorage`: `Onboarding.remindKey`, `dayKey`, `remindMinutesKey`, `remindEveKey`, `DCAReminders.showAmountKey`, `monthlyKey` and `symbolKey`.
  - It adds `.task(id: reminderInputs) { … }`, which calls `await DCAReminders.sync(reminderInputs)` unless `store.recordsLocked`.
  - The `.task(id: phase)` active branch calls the same sync before the `--ui-testing` guard. Under `--ui-testing`, `sync` returns at once.
- Create test: `Tests/DCARemindersTests.swift`

**Interfaces:**
- Consumes: Task 4 `DCAReminderInputs`, `DCAReminderPlan`; Task 1 `QuickDCA.defaults`, `Portfolio.dcaLogged(in:)`.
- Produces:
  - `enum DCAReminders` gains these members:
    - `static let showAmountKey = "dcaReminder.showAmount"`.
    - `static func inputs(_ p: Portfolio, defaults: UserDefaults = .standard, now: Date = Date()) -> DCAReminderInputs?`. Returns nil when the remind key is off or the day is not in `Onboarding.days`. `showAmount` reads as true when the key is absent. Amount and symbol come from `QuickDCA.defaults` (preset, then onboarding). `loggedThisMonth` is `p.dcaLogged(in: YearMonth(now))`.
    - `static func ownIDs(in pending: [String]) -> [String]`: the ids that start with `DCAReminderPlan.prefix`, which includes the two legacy ids.
    - `static func sync(_ inputs: DCAReminderInputs?) async`. It removes `ownIDs` of the pending requests, which covers the §10.10 migration, then adds `DCAReminderPlan.requests(inputs, now: Date())` as `UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)`, with `content.userInfo = request.userInfo` and `.sound = .default`. nil only removes.
    - `static func clear() async`, which is the same as `sync(nil)`.
  - `DividendReminders.limit == 40`.

- [ ] **Step 1: Write `DCARemindersTests`** (a fresh `UserDefaults(suiteName:)` per test; no notification center is touched)

```swift
func testInputsOffWhenReminderOff()   // remind false → nil; remind true, day 0 → nil
func testInputsFromSettingsAndPreset() {
    // remind true, day 6, minutes 540, eve true, showAmount unset; data.quickDCA {0050, 5000, ""}
    // → DCAReminderInputs(day: 6, minutes: 540, dayBefore: true, showAmount: true, amount: 5000, symbol: "0050", month: YearMonth(now).key, loggedThisMonth: false)
}
func testInputsFallBackToOnboardingValues()  // no preset; onboarding.symbol "006208", monthly 3000 → amount 3000, symbol "006208"
func testShowAmountOff()                      // key false → showAmount false
func testLoggedThisMonthFollowsTheRecords()   // dcaMonths ∋ now and a .buy this month → true; the trade removed → false
func testOwnIDsIncludeLegacy() {
    XCTAssertEqual(DCAReminders.ownIDs(in: ["dca-reminder", "dca-reminder-eve", "dca-reminder-2026-12", "dca-reminder-eve-2026-12", "dividend-ABC", "price-alert-1"]),
                   ["dca-reminder", "dca-reminder-eve", "dca-reminder-2026-12", "dca-reminder-eve-2026-12"])
}
func testDividendReminderCapLeavesRoomForDCA() { XCTAssertEqual(DividendReminders.limit, 40); XCTAssertLessThanOrEqual(DividendReminders.limit + 24, 64) }
func testResetClearsShowAmount()              // Onboarding.keys contains DCAReminders.showAmountKey
```

Also extend `testReminderCenterHasTheDebitDayReminder` in `UITests/ETFToGoUITests.swift`: the `reminder-dca-show-amount` switch exists, and its value is "1" after the reminder is turned on.

- [ ] **Step 2: Implement per Interfaces.** Onboarding's reminder toggle still asks for permission, as it does today.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Onboarding/OnboardingFlow.swift App/ToolsView.swift App/ETFToGoApp.swift Tests/DCARemindersTests.swift UITests/ETFToGoUITests.swift
git commit -m "feat(reminders): one-shot monthly reminders from the records, amount optional"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green.

---

### Task 6: A tapped reminder opens the sheet

**Files:**
- Modify: `App/Member/PriceAlertMonitor.swift`.
  - Replace `PriceAlertPresenter` with `NotificationRouter`.
  - `PriceAlertMonitor.start` no longer sets the delegate.
- Create: `App/Lobby/AppRouter.swift`
- Modify: `App/ETFToGoApp.swift`.
  - `init` sets `UNUserNotificationCenter.current().delegate = NotificationRouter.shared` on every launch, including `--ui-testing`.
  - `--ui-testing --open quickDCA` sets `AppRouter.shared.quickDCARequested = true`.
  - `RootView` returns to the lobby when a request arrives: `.onChange(of: router.quickDCARequested) { if $1 { navigation.toLobby() } }`.
- Modify: `App/Lobby/LobbyView.swift`. When `router.quickDCARequested`, the lobby presents the sheet once it is on screen and `!covered && !store.recordsLocked`, then clears the request. While locked, it clears the request and stays on the lobby.
- Create test: `Tests/NotificationRouterTests.swift`
- Modify: `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Produces:
  - `@MainActor final class AppRouter: ObservableObject { static let shared = AppRouter(); @Published var quickDCARequested = false }`.
  - `final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate`, with `static let shared`.
    - `static func presentation(for identifier: String) -> UNNotificationPresentationOptions` returns `[.banner, .list, .sound]` for ids with prefix `PriceAlertMonitor.notificationPrefix` or `DCAReminderPlan.prefix`, and `[]` otherwise. `willPresent` uses it.
    - `static func wantsQuickDCA(_ userInfo: [AnyHashable: Any]) -> Bool` is true when `userInfo["route"] as? String == "quickDCA"`.
    - `didReceive` sets `AppRouter.shared.quickDCARequested = true` on the main actor when `wantsQuickDCA`, then calls the completion handler.

- [ ] **Step 1: Write the failing tests**

```swift
// NotificationRouterTests
func testPresentation() {
    XCTAssertEqual(NotificationRouter.presentation(for: "price-alert-1"), [.banner, .list, .sound])
    XCTAssertEqual(NotificationRouter.presentation(for: "dca-reminder-2026-12"), [.banner, .list, .sound])
    XCTAssertEqual(NotificationRouter.presentation(for: "dca-reminder-eve-2026-12"), [.banner, .list, .sound])
    XCTAssertEqual(NotificationRouter.presentation(for: "dividend-ABC"), [])
}
func testRoute() {
    XCTAssertTrue(NotificationRouter.wantsQuickDCA(["route": "quickDCA"]))
    XCTAssertFalse(NotificationRouter.wantsQuickDCA(["route": "other"])); XCTAssertFalse(NotificationRouter.wantsQuickDCA([:]))
}
// ETFToGoUITests
func testReminderRouteOpensQuickDCAOverLobby() {
    // launch ["--demo-streak", "3", "--demo-unlogged", "--demo-held", "-onboarding.monthly", "5000", "--open", "quickDCA"]
    // quick-dca-save exists (10 s); swipe the sheet down → lobby-find is hittable
}
```

- [ ] **Step 2: Implement per Interfaces.** Keep `PriceAlertMonitorTests` passing; rename any reference to `PriceAlertPresenter` there.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Member/PriceAlertMonitor.swift App/Lobby/AppRouter.swift App/ETFToGoApp.swift App/Lobby/LobbyView.swift Tests/NotificationRouterTests.swift Tests/PriceAlertMonitorTests.swift UITests/ETFToGoUITests.swift
git commit -m "feat(reminders): tapping the debit-day reminder opens 記一筆 in the lobby"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. The CI artifact `ETFToGo-screens/screen-quick-dca.png` shows the sheet over the lobby.
