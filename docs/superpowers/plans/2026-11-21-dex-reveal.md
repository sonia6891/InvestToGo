# Dex Card Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first visit to an ETF's 詳情 no longer shows a one-line toast. A full-screen reveal plays instead: the card back flips to the card face, the reward rises, and the person picks 「收下」 or 「看圖鑑」.

**Architecture:** A small reveal model (phases, start phase, reward text) is unit-tested. `DexRevealView` reuses the existing `DexCard` face, which becomes internal, and is presented as a full-screen cover from `FundDetail`. Collecting and paying stay exactly where they are (`store.collectDexCard` on `onAppear`): the reveal only shows what already happened.

**Tech Stack:** SwiftUI (iOS 18: `keyframeAnimator`/`rotation3DEffect`), XCTest, XCUITest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-habit-loop-and-polish-design.md` (Traditional Chinese, binding). This plan is delivery item §12.3 and implements §7, with ruling §10.8.

## Global Constraints

- All copy is Traditional Chinese (Taiwan usage). Say 「外觀主題」, never 「皮膚」 (§9).
- No new third-party packages (§9).
- No network changes (§9).
- Motion follows the living-lobby rules (§9, §7):
  - With Reduce Motion (`@Environment(\.motionReduced)`), the face fades straight in, with no flip, scale or particles.
  - With `--ui-testing`, the final state shows at once, with the face, the reward and both buttons.
  - Low Power Mode changes nothing here, because the reveal has no ambient motion.
- A tap anywhere on the reveal while it plays jumps to the final state. It never blocks 「收下」.
- Experience and the card are given exactly as today, on opening the 詳情 (`collectDexCard` in `FundDetail.onAppear`). The reveal is presentation only. If the app is closed mid-reveal, both are already saved and the reveal is not replayed (§10.8).
- Only one card flips at a time, over the 詳情. 「收下」 returns to the 詳情 (§7).
- The reveal is a big event, but it never overlaps LEVEL×UP, which is shown only over the lobby. Nothing to change there; do not present LEVEL×UP from this screen (§7).
- `--quiet-toasts` (the CI skin matrix and store screens) shows no reveal, exactly as it showed no toast.
- Never celebrate price movement (§1): the reveal shows the card's facts and the experience, never a price change.
- Exact copy:
  - card back 「ETF 圖鑑」;
  - reward 「+30 經驗」 (the earned amount, `FundVisit.cardXP`), or 「收進圖鑑」 when this month's limit is used up;
  - buttons 「收下」 and 「看圖鑑」.
- Accessibility identifiers: `dex-reveal` (the container), `dex-reveal-accept`, `dex-reveal-open`. Every existing identifier keeps its name. Decorative layers are `accessibilityHidden(true)`.
- Commits: stage named paths only. Never use `git add -A`; an untracked, locally ignored `marketing/` folder belongs to other work.
- Before Task 1: the working tree carries uncommitted 「皮膚 → 外觀主題」 copy edits in seven files, including `UITests/ETFToGoUITests.swift`. The controller commits or stashes them first.
- Verification is CI only; there is no local Swift toolchain. Every task ends with these steps:
  1. `git add <named paths>` and `git commit`.
  2. `git push origin <branch>`, where the branch is the controller's working branch cut from `claude/living-lobby`.
  3. `gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>`.
  4. The jobs `core`, `simulator` and `skin-matrix` are green.

## Review Focus

1. **Largest accessibility text size.** 「收下」 and 「看圖鑑」 must stay on screen and hittable, so the reveal scrolls when needed (Task 2: `testLargestTextMainFlow` now accepts the reveal by tapping `dex-reveal-accept`).
2. **Returning to a 詳情 already collected**, for example after 「看圖鑑」 and back, or after a 走勢 tab switch. No second reveal (Task 2 UI test `testDexRevealOnlyOnFirstVisit`).
3. **The fourth new card in a month.** No experience is paid, and the reward line reads 「收進圖鑑」, never 「+0 經驗」 (Task 1 test `testRewardText`).
4. **VoiceOver.** The reveal is read as one sentence with the fund and the reward, and focus lands on 「收下」, never on the decorative back (Task 1 test `testSpokenSummary`).
5. **A dark skin (black-gold, pixel).** The card back and face keep their contrast on the cover's backdrop. Check in the screenshot added in Task 2, in all four skins.

---

### Task 1: Reveal model and view

**Files:**
- Create: `App/Dex/DexRevealView.swift`
- Modify: `App/Dex/DexCardView.swift`. `private struct DexCard` becomes `struct DexCard`, internal, with the same initializer `DexCard(fund:facts:among:)`.
- Create test: `Tests/DexRevealTests.swift`
- Modify: `Tests/GameTriggerStoreTests.swift`. The two `FundDetail.toastText` asserts move to `DexReveal.rewardText`.

**Interfaces:**
- Produces:
  - `enum DexRevealPhase: Int, Comparable { case back, face, reward, buttons }`.
  - `enum DexReveal`:
    - `static func start(reduceMotion: Bool, uiTesting: Bool) -> DexRevealPhase`: `.buttons` under UI testing, `.face` under Reduce Motion, otherwise `.back`.
    - `static func rewardText(_ visit: FundVisit) -> String`: 「+\(cardXP) 經驗」 when `cardXP > 0`, else 「收進圖鑑」.
    - `static func spoken(_ fund: Fund, visit: FundVisit) -> String`: 「收進圖鑑：\(fund.id) \(fund.name)，\(rewardText)」. When no experience was paid, it is 「收進圖鑑：0050 元大台灣50」 with no trailing reward.
  - `struct DexRevealItem: Identifiable, Equatable { let symbol: String; let visit: FundVisit; var id: String { symbol } }`. `FundVisit` is already `Equatable`.
  - `struct DexRevealView: View { init(item: DexRevealItem, onAccept: @escaping () -> Void, onOpen: @escaping () -> Void) }`.
    - Back: the skin's `SkinDecor(page: .other)` pattern and `SkinImage(.badge)`, with 「ETF 圖鑑」 in the skin's title font.
    - Flip: `rotation3DEffect` about the y axis to the `DexCard` face. Facts come from `store.dexFacts()` and `store.dexFunds`, built once in `.task`.
    - Reward line, then the two buttons: 「收下」 with `SkinButtonStyle(primary: true)` (`dex-reveal-accept`) and 「看圖鑑」 (`dex-reveal-open`).
    - Phases advance on a timer the view owns; timings are the implementer's (§11).
    - `ConfirmFeedback.confirm(skin)` plays once when the face lands, and not under `--ui-testing`.
    - The face is wrapped in a `ScrollView` with `.scrollBounceBehavior(.basedOnSize)`.
    - The container is `.accessibilityElement(children: .contain)` with id `dex-reveal`. A combined summary element reads `DexReveal.spoken`, and `@AccessibilityFocusState` puts focus on 「收下」 once `.buttons` is reached.

- [ ] **Step 1: Write `DexRevealTests`**

```swift
func testStartPhase() {
    XCTAssertEqual(DexReveal.start(reduceMotion: false, uiTesting: true), .buttons)
    XCTAssertEqual(DexReveal.start(reduceMotion: true, uiTesting: false), .face)
    XCTAssertEqual(DexReveal.start(reduceMotion: true, uiTesting: true), .buttons)
    XCTAssertEqual(DexReveal.start(reduceMotion: false, uiTesting: false), .back)
}
func testRewardText() {
    XCTAssertEqual(DexReveal.rewardText(FundVisit(new: true, cardXP: 30)), "+30 經驗")
    XCTAssertEqual(DexReveal.rewardText(FundVisit(new: true, cardXP: 0)), "收進圖鑑")
}
func testSpokenSummary() {
    let fund = Fund(id: "0050", name: "元大台灣50", strategy: .saving)
    XCTAssertEqual(DexReveal.spoken(fund, visit: FundVisit(new: true, cardXP: 30)), "收進圖鑑：0050 元大台灣50，+30 經驗")
    XCTAssertEqual(DexReveal.spoken(fund, visit: FundVisit(new: true, cardXP: 0)), "收進圖鑑：0050 元大台灣50")
}
func testRevealRendersInEverySkin()  // ImageRenderer of DexRevealView(item: 0050, 30) at 390×844 for each Skins.all, environment(\.skin) set → non-nil uiImage
```

- [ ] **Step 2: Implement per Interfaces.** Delete `FundDetail.toastText` only in Task 2, where its caller goes. For this task, the `GameTriggerStoreTests` asserts point at `DexReveal.rewardText` while `toastText` still exists.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Dex/DexRevealView.swift App/Dex/DexCardView.swift Tests/DexRevealTests.swift Tests/GameTriggerStoreTests.swift
git commit -m "feat(dex): the card reveal: back, flip, face, reward, 收下 / 看圖鑑"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green.

---

### Task 2: The first 詳情 visit plays the reveal

**Files:**
- Modify: `App/DiscoverViews.swift`. In `FundDetail`:
  - `onAppear` sets `reveal = DexRevealItem(symbol: fund.id, visit: visit)` when `visit.new && !DemoArguments.quietToasts`, instead of `store.pendingNotice`.
  - `.fullScreenCover(item: $reveal)` presents `DexRevealView` with `.environmentObject(store)`, `.environment(\.skin, skin)`, and `.preferredColorScheme` from `SkinStore.shared`.
  - 「收下」 sets `reveal = nil`. 「看圖鑑」 sets `reveal = nil`, then `navigation.push(.dexCard(fund.id))` after the cover has dismissed (in `onDismiss`, keyed by a `@State` flag).
  - Under Reduce Motion the cover is presented and dismissed inside a transaction with `disablesAnimations = true`.
  - `static func toastText` is removed.
- Modify: `UITests/ETFToGoUITests.swift`.
  - Add `private func acceptDexReveal(_ app: XCUIApplication)`, which waits up to 5 s for `dex-reveal-accept` and taps it.
  - Call it after the first open of a fund's 詳情 in `testOTCCatalogAndRestoredResearchNavigation`, `testAnnualFeesAndHistoryNavigation`, `testFindDetailAndDex` (replace its toast asserts), `testFindDetailAndDexInEverySkin` and `testLargestTextMainFlow`.
  - Any other test that opens a 詳情 for the first time in a run without `--quiet-toasts` gets the same call; CI names them.
  - Add the new tests below.
- Modify: `.github/workflows/native-ui.yml`. In "Capture the lobby and every feature screen", add `screen-dex-reveal.png` launched with `--ui-testing --reset --skip-onboarding --open detail --symbol 0050` (no `--quiet-toasts`). In "Capture the skin kit sheet in every skin", or in a new loop over the four skins in the same step, add `dex-reveal-<skin>.png` with `--skin <skin>`.

**Interfaces:**
- Consumes (Task 1): `DexRevealItem`, `DexRevealView(item:onAccept:onOpen:)`, `DexReveal.rewardText`.

- [ ] **Step 1: Write the UI tests**

```swift
func testDexRevealOnFirstVisit() {
    // launch ["--open", "find"]; search "0050", tap 元大台灣50
    // dex-reveal exists (5 s); static text "+30 經驗" exists; static text "ETF 圖鑑" may be gone (final state)
    // dex-reveal-accept.isHittable; tap it → detail-code label "0050", dex-reveal gone
}
func testDexRevealOnlyOnFirstVisit() {
    // as above, accept; back to the list, tap 元大台灣50 again → detail-code exists, dex-reveal does not appear within 3 s
}
func testDexRevealOpensTheCard() {
    // launch ["--open", "detail", "--symbol", "0050"]; tap dex-reveal-open → dex-bar-fee exists (5 s)
}
func testFourthCardThisMonthSaysCollected() {
    // visit 0050, 006208, 0056 (accept each), then 00878 → static text "收進圖鑑" exists inside dex-reveal, no "+30 經驗"
}
```

- [ ] **Step 2: Implement per Files.**

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/DiscoverViews.swift UITests/ETFToGoUITests.swift .github/workflows/native-ui.yml
git commit -m "feat(dex): a fund's first 詳情 plays the card reveal instead of a toast"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. `ETFToGo-screens` holds `screen-dex-reveal.png` and `dex-reveal-<skin>.png` for all four skins, each showing the face, 「+30 經驗」 and both buttons. The skin-matrix `detail` shots (`--quiet-toasts`) are unchanged.
