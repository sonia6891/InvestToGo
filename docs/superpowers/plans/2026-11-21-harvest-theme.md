# 「收成」 Ex-Dividend Season Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fifth 外觀主題, 「收成」 (`harvest`, 「SKN 005」), in a cut-paper rice-harvest style. It unlocks for good with the achievement 「除息季限定外觀主題」: record a dividend whose payment date falls in July, August or September (Taipei time). Members can wear it straight away.

**Architecture:**
- Unlock: PocketCore gains a third unlock kind, `achievement(id)`. A new `GameState.recordDividendSeason` counts the season and unlocks the achievement. It runs at every launch, through `migrate`, and in every store write that adds or changes a dividend.
- Art: one Node script with no dependencies generates the vector art. `Scripts/export_skin_art.py` imports it, as it does for 縫線 and 手繪.
- The skin itself: a `skins.json` entry, one new decoration kind and one new motion personality.
- The 外觀主題 page: it shows the season condition all year round, never 「即將推出」.

**Tech Stack:** Swift (PocketCore and SwiftPM on Linux; SwiftUI app), Node 24 (plain ES modules), Python 3 export script, XCTest/XCUITest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-21-habit-loop-and-polish-design.md` (Traditional Chinese, binding). This plan is delivery item §12.5 and implements §8, with ruling §10.1.

## Global Constraints

- All copy is Traditional Chinese (Taiwan usage). Say 「外觀主題」, never 「皮膚」 (§9).
- No new third-party packages (§9). The art script imports only `node:fs` and `node:path`, with no npm install.
- No network changes (§9).
- Skin facts (§8):
  - id `harvest`, name 「收成」, code 「SKN 005」.
  - Style: cut paper and rice farming, in warm gold (rice ears), rice green, rice-white paper and dark brown ink.
  - Objects are rice ears, harvest baskets, a granary, a bamboo sieve, a bamboo hat (斗笠) and the like.
  - The digits are cut-paper vector digits.
- Art: generated vector SVG from one script in `design/3d/skins/harvest/`. It covers all 13 `SkinArtName`s, 10 digits and the badge, and is imported by `Scripts/export_skin_art.py` (§8, §2).
- Motion: like rice ears in the wind, a slow, soft sway. The particles are falling grains (§8). The lobby-motion rules for Reduce Motion, Low Power Mode and UI testing stay as they are (§9).
- Sound and haptics: reuse the lightest existing pair, `scribble` and `faint`. No new assets (§8).
- Unlock (§8, §10.1):
  - A dividend whose **payment date** (`Dividend.date`) falls in months 7–9 in `GameRules.taipei`, in any year and with any status, counts as soon as it is saved through any existing dividend flow. The day it was typed in does not matter.
  - It is not subject to the monthly experience cap and pays no experience.
  - On the first launch after the update, a dividend already in the records counts.
  - Once reached it stays unlocked for good. Members may wear the theme without it.
- Until it is reached, the 外觀主題 page shows 「7–9 月記一筆配息解鎖」 all year round, never 「即將推出」. The achievement shows on the wall from this version on (§8).
- Store screenshots and the store description are out of scope (§8).
- Every skin keeps `ink`/`sub` ≥ 4.5:1 and `up`/`down` ≥ 3:1 on `page` (the existing `testSkinTextContrast`).
- Commits: stage named paths only. Never use `git add -A`; an untracked, locally ignored `marketing/` folder belongs to other work.
- Before Task 1: the working tree carries uncommitted 「皮膚 → 外觀主題」 copy edits in seven files, including `Achievements.swift` (title 「除息季限定外觀主題」) and `UITests/ETFToGoUITests.swift`. The controller commits or stashes them first.
- Local tools on the Windows machine: `py` for Python (there is no `python3`) and `node`. Swift runs only in CI.
- Verification is CI only for Swift. Every task ends with these steps:
  1. `git add <named paths>` and `git commit`.
  2. `git push origin <branch>`, where the branch is the controller's working branch cut from `claude/living-lobby`.
  3. `gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>`.
  4. The jobs `core`, `simulator` and `skin-matrix` are green.

## Review Focus

1. **The Taipei month edge.** A payment at 2026-06-30T16:30Z, which is 7/1 00:30 in Taipei, counts. One at 2026-09-30T16:30Z, which is 10/1 in Taipei, does not (Task 1 `testSeasonUsesTaipeiMonths`).
2. **Editing a dividend's date into the season**, or importing a backup that holds one. This counts at once, not only at the next launch (Task 1 `testEditedDateCounts`, and Task 3 `testImportedBackupUnlocks`).
3. **A member whose membership lapses while wearing 收成.** With the achievement they keep it. Without it they go back to black-gold, with the existing lapse notice (Task 3 `testLapsedMemberKeepsAnEarnedHarvest`).
4. **Largest accessibility text on the 外觀主題 page.** 「7–9 月記一筆配息解鎖」 wraps and stays readable. The badge caption carries no digits, so the "no figures on cards or badges" check holds (Task 4, the existing `testCarouselShowsNoNumbers` with five skins).
5. **The fifth skin in every per-skin loop.** Every place that lists the skins must name harvest: CI shots, UI tests and the contact sheet. Otherwise a broken harvest screen ships untested (Task 4 counts 65 matrix shots).

---

### Task 1: The season unlock in PocketCore

**Files:**
- Modify: `PocketCore/Sources/PocketCore/Design/Skins.swift`
  - `SkinUnlock` gains `case achievement(String)`, decoded from `{"kind": "achievement", "id": "<achievement id>"}`. A missing `id` throws, as the strict decoder does elsewhere.
  - `Skins.isUnlocked(_ skin: Skin, level: Int, member: Bool, achievements: Set<String>) -> Bool`. The new parameter is required, with no default. `.achievement(let id)` is `member || achievements.contains(id)`.
- Modify: `PocketCore/Sources/PocketCore/Game/Achievements.swift`. `exDividendSkin` loses `comingSoon: true`. Update the doc comment that cites 「除息季限定皮膚」 to 「除息季限定外觀主題」.
- Modify: `PocketCore/Sources/PocketCore/Game/GameTriggers.swift`. Add `recordDividendSeason`, and call it at the end of `migrate(_:now:)` on every run, not behind the `migration < 1` gate.
- Create test: `PocketCore/Tests/PocketCoreTests/DividendSeasonTests.swift`
- Modify tests:
  - `GameTriggerTests.testAchievementsWithoutAFeatureAreComingSoonAndNeverUnlock`: the comingSoon set becomes `["checkupDone", "yearReport"]`, and the loop drops `exDividendSkin`.
  - `QuestAchievementTests.testCounterAchievements`: `exDividendSkin` moves to the unlocked list, because its counter is 1 and its goal is 1.
  - `MemberFeatureTests.testUpcomingContentIsHidden`: the wall gains `"exDividendSkin"` after `"dexCollector"`, and the count becomes `all.count - 2`.
  - `PocketDesignTests.testIsUnlocked`: it passes `achievements: []`.
  - `UITests/ETFToGoUITests.swift` `testAchievementWall`, because 除息季限定外觀主題 is now on the wall:
    - the count suffix becomes `" / 9"`;
    - the hidden list is `["checkupDone", "yearReport"]`;
    - add `achievement-exDividendSkin` exists with value `"0 / 1"`;
    - its comment no longer says 除息季 is hidden.
- Modify: the two app callers of `isUnlocked`, `App/Design/SkinStore.swift:40` and `App/Skins/SkinCarousel.swift:9`. For now they pass `achievements: []`, which keeps today's behaviour, because no skin uses the new kind yet. Task 3 wires in the real set.

**Interfaces:**
- Produces:
  - `SkinUnlock.achievement(String)`.
  - `Skins.isUnlocked(_:level:member:achievements:)`.
  - `extension GameState { @discardableResult mutating func recordDividendSeason(_ p: Portfolio, now: Date) -> Bool }`:
    - It returns true only on the call that unlocks.
    - When `counter(.exDividendSeason) == 0` and some `p.dividends` has `GameRules.taipei.component(.month, from: date)` in `7...9`, it calls `count(.exDividendSeason)` and sets `unlocked["exDividendSkin"] = now` when that is still nil.
    - It never touches `xp`, `coins` or `xpByMonth`.
  - `static let exDividendSkinID = "exDividendSkin"` on `Achievements`, so that `skins.json` and Swift share one spelling.

- [ ] **Step 1: Write `DividendSeasonTests`.** `now` is 2026-11-21 12:00 Taipei, and `dividend(_ iso: String)` makes a `.paid` 0056 dividend at that instant.

```swift
func testPaymentInSeasonUnlocks() {
    var g = GameState(); let p = portfolio([dividend("2026-08-15T02:00:00Z")])
    XCTAssertTrue(g.recordDividendSeason(p, now: now))
    XCTAssertEqual(g.counter(.exDividendSeason), 1); XCTAssertEqual(g.unlocked["exDividendSkin"], now)
}
func testOutsideSeasonDoesNot()   // 2026-06-15, 2026-10-02, 2026-12-25 → false, counter 0, unlocked nil
func testSeasonUsesTaipeiMonths() {
    // 2026-06-30T16:30:00Z is 2026-07-01 00:30 Taipei → true
    // 2026-09-30T16:30:00Z is 2026-10-01 00:30 Taipei → false
}
func testAnyYearAndAnyStatusCount()     // 2023-09-10 .paid → true; fresh state, 2027-07-20 .estimated → true
func testOnlyOnce()                     // second call (later now) → false; counter 1; unlocked date still the first now
func testPaysNoExperience()             // xp, coins, xpByMonth equal before and after
func testEditedDateCounts()             // p with a 2026-06-10 dividend → false; same id with date 2026-07-10 → true
func testMigrateCountsOldRecords() {
    var g = GameState(); g.migration = GameMigration.current   // already migrated before this version
    g.migrate(portfolio([dividend("2025-08-05T02:00:00Z")]), now: now)
    XCTAssertNotNil(g.unlocked["exDividendSkin"])
}
func testMigrateTwiceIsStable()         // migrate twice → GameState equal after the first and the second
func testAchievementDecodesAndUnlocks() {
    // decode {"kind":"achievement","id":"exDividendSkin"} → .achievement("exDividendSkin")
    // decode {"kind":"achievement"} → throws
    // isUnlocked(skinWith(.achievement("exDividendSkin")), level: 1, member: false, achievements: []) == false
    // … achievements: ["exDividendSkin"] → true; member: true, achievements: [] → true
}
```

- [ ] **Step 2: Implement per Interfaces.** Update the `isUnlocked` doc comment: 收成 opens with its achievement or for members.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add PocketCore/Sources/PocketCore/Design/Skins.swift PocketCore/Sources/PocketCore/Game/Achievements.swift PocketCore/Sources/PocketCore/Game/GameTriggers.swift PocketCore/Tests/PocketCoreTests/DividendSeasonTests.swift PocketCore/Tests/PocketCoreTests/GameTriggerTests.swift PocketCore/Tests/PocketCoreTests/QuestAchievementTests.swift PocketCore/Tests/PocketCoreTests/MemberFeatureTests.swift PocketCore/Tests/PocketCoreTests/PocketDesignTests.swift App/Design/SkinStore.swift App/Skins/SkinCarousel.swift
git commit -m "feat(game): 除息季 counts a July–September payment and unlocks its theme for good"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Add `UITests/ETFToGoUITests.swift` to the `git add` above. Expected: all three jobs green.

---

### Task 2: The 收成 art

**Files:**
- Create: `design/3d/skins/harvest/harvest.mjs`. Running `node design/3d/skins/harvest/harvest.mjs <dir>` writes the SVGs into `<dir>`. Output is deterministic, using a fixed-seed PRNG in the script, so re-running gives byte-identical files.
- Create: the generated SVGs in `design/3d/skins/harvest/`:
  - `dollar.svg`, `pocket_icon.svg`, `badge.svg`, `patch.svg`;
  - `icon_magnifier.svg`, `icon_stack.svg`, `icon_calc.svg`, `icon_bars.svg`, `icon_bell.svg`, `icon_target.svg` and `icon_crown.svg`, the `ICONS` stems in `export_skin_art.py`;
  - `digit_0.svg` … `digit_9.svg`.
- Modify: `Scripts/export_skin_art.py`.
  - `mapping("harvest")` follows the vector branch with `src = SK / "harvest"`, `badge = src / "badge.svg"`, and extras `digit_0…9` plus `patch`.
  - `SKINS` appends `"harvest"`.
  - Add the harvest line to the docstring's source list.
- Create: `App/Assets.xcassets/Skins/harvest/*.imageset`, written by `py Scripts/export_skin_art.py`, which rebuilds the whole `Skins` folder. Commit only `App/Assets.xcassets/Skins/harvest`. If `git status` shows any other skin's imagesets changed, stop and report: the export must be a no-op for them.
- Modify: `.github/workflows/native-ui.yml`. The `core` job gains "The harvest art is reproducible": it runs `node design/3d/skins/harvest/harvest.mjs "$RUNNER_TEMP/harvest"`, then `diff -r "$RUNNER_TEMP/harvest" design/3d/skins/harvest --exclude=harvest.mjs`.

**Interfaces:**
- Produces: the asset names `Skins/harvest/<SkinArtName>`, `Skins/harvest/digit_N` and `Skins/harvest/patch`, for Task 3.
- SVG conventions, taken from `stitch.mjs`:
  - Icons use `viewBox="-22 -22 244 244" width="400" height="400"`. Digits use `viewBox="-22 -22 130 160" width="172" height="232"`.
  - Every shape has a soft paper shadow: the same path, `fill="rgba(80,52,24,.24)"`, `transform="translate(3 4)"`. The export turns `rgba()` into color plus opacity.
  - Only `fill`/`stroke` colors from the palette: gold `#E9C46A`, deep gold `#B7791F`, rice green `#5E7D32`, paper `#FFFAEC`, ink `#3A2614`. No gradients, filters or text elements, because CoreSVG drops them.
  - The cut-paper look comes from slightly irregular polygon edges, using PRNG jitter of ±1.5 units on the vertices, and from a lighter inner layer inset 6 units.

The subjects per name are a suggestion; the drawings are the implementer's (§11).

| name | stem | subject |
|---|---|---|
| hero_dollar | `dollar` | a coin stamped with a rice ear |
| pocket, pocket_icon | `pocket_icon` | a woven harvest basket with ears spilling out |
| find | `icon_magnifier` | a bamboo sieve (竹篩) |
| dividends | `icon_stack` | a bundle of rice sheaves |
| tools, calc | `icon_calc` | a wooden grain measure (斗) |
| fees | `icon_bars` | three stalks of rising height |
| reminder | `icon_bell` | a granary bell |
| achievements, goal | `icon_target` | a granary (穀倉) |
| crown | `icon_crown` | a bamboo hat (斗笠) |
| badge | `badge` | a round paper seal with a rice ear |
| — | `patch` | a rice-paper slip that the digits sit on, as stitch's cloth patch does |
| — | `digit_N` | cut-paper digits, gold on a deep-gold under-layer |

- [ ] **Step 1: Write `harvest.mjs` and run it.** `node design/3d/skins/harvest/harvest.mjs design/3d/skins/harvest` must print one line per file, 23 files in all. A second run must change nothing (`git status` clean for that folder after a commit).

- [ ] **Step 2: Export.** Run `py Scripts/export_skin_art.py`. Expected: no missing-source errors, and 23 imagesets under `App/Assets.xcassets/Skins/harvest`. `pocket` and `pocket_icon` share a source, as in the vector branch, which gives 13 + 10 + 1 = 24 names from 23 files.

- [ ] **Step 3: Look at every SVG.** Open the folder in the browser, or render it with `node` to an HTML contact page in the scratchpad. Check that none is blank, clipped or off-palette.

- [ ] **Step 4: Commit, push, run CI**

```bash
git add design/3d/skins/harvest Scripts/export_skin_art.py App/Assets.xcassets/Skins/harvest .github/workflows/native-ui.yml
git commit -m "art(harvest): 收成's cut-paper rice art, generated and exported"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green, and the `core` job's reproducibility diff is empty.

---

### Task 3: The 收成 skin

**Files:**
- Modify: `PocketCore/Sources/PocketCore/Resources/skins.json`. Append this entry last:

```json
{ "id": "harvest", "name": "收成", "code": "SKN 005",
  "colors": { "page": "#F5EEDC", "ink": "#3A2614", "sub": "#6B5536", "dim": "#A89878", "card": "#FFFAEC", "line": "#E3D6B4",
              "accent": "#B7791F", "up": "#B0322A", "down": "#2F6B3A", "extra": ["#5E7D32", "#E9C46A", "#FFFAEC"] },
  "fonts": { "big": "BreeSerif-Regular", "title": "NotoSerifTC-Bold", "body": "NotoSerifTC-Medium", "mono": "BreeSerif-Regular" },
  "style": { "tag": "paperStrip", "button": "paperStitch", "stage": "paperDisc", "check": "stitchDisc", "quick": "stitchDisc", "chart": "plain", "decor": "stalks" },
  "art": { "kind": "vector", "folder": "Skins/harvest" },
  "feedback": { "sound": "scribble", "haptic": "faint" },
  "unlock": { "kind": "achievement", "id": "exDividendSkin" },
  "burst": ["#E9C46A", "#B7791F", "#5E7D32", "#FFFAEC"] }
```

  The contrasts on `page`: ink 12.37, sub 6.09, up 5.44 and down 5.52. There is no `metal`.
- Modify: `PocketCore/Sources/PocketCore/Design/Skins.swift`. `DecorKind` gains `stalks`.
- Modify: `App/Design/SkinComponents.swift`. `SkinDecor` adds `case .stalks: stalks(&context, frame)`: a few thin rice stalks with drooping ears rising from the bottom corners, drawn in `extra[0]` (rice green) and `extra[1]` (gold) at the opacity the `seams` decor uses.
- Modify: `App/Design/Motion.swift`:
  - `MotionParticle` gains `.grain`.
  - `SkinMotion` gains `var sway: Double = 0`, in degrees.
  - `case "harvest": SkinMotion(bounce: 0.1, stepped: false, stepsPerSecond: 0, bobAmplitude: 2, particle: .grain, jitter: false, sway: 2.5)`.
  - `AmbientBob` adds `sin(cycle·2π + π/2) × sway` to the rotation, with `anchor: .bottom` when `sway > 0`, so objects lean like stalks rather than spin.
  - `AmbientParticles`, for `.grain`: `y` runs top → bottom (falling) rather than rising, and each grain is a 2:1 ellipse rotated by its seed. It uses tint `extra[1]` when present.
- Modify: `App/Design/SkinStore.swift`. `takeOffLocked(level:member:achievements: Set<String>)`.
- Modify: `App/Membership/MemberView.swift`. `MembershipStore` gains `var achievements: () -> Set<String> = { [] }`, and line 131 passes `achievements()`.
- Modify: `App/ETFToGoApp.swift`. Next to `membership.level`, add `membership.achievements = { [weak store] in Set((store?.data.game?.unlocked ?? [:]).keys) }`.
- Modify: `App/Models.swift`. Before `try commit(next)` in `record(_:)`, `saveDividend`, `markPaid`, `confirmPaid` and `importBackup`, run `var game = next.game ?? GameState(); if game.recordDividendSeason(next, now: Date()) { next.game = game }`. Write it once as a private `func withDividendSeason(_ next: inout Portfolio, now: Date)`; `saveDividend` passes its `now`.
- Modify tests:
  - `Tests/SkinArtTests.swift`: count 5; `extraNames` for harvest is the digits plus `patch`; add `XCTAssertEqual(extraNames(Skins.named("harvest")).count, 11)`.
  - `Tests/SkinKitTests.swift:25` and `Tests/PocketReportViewTests.swift:27`: count 5.
  - `Tests/MotionTests.swift`: add the harvest assertions.
  - `PocketDesignTests`:
    - `testFourSkinsInOrder` is renamed `testFiveSkinsInOrder`: ids gain `"harvest"`, names gain `"收成"`.
    - `testColorsMatchSpec`: add harvest `page 0xF5EEDC`, `ink 0x3A2614`, `accent 0xB7791F`, `extra [0x5E7D32, 0xE9C46A, 0xFFFAEC]`.
    - `testUnlockRules`: add `.achievement("exDividendSkin")`.
    - `testIsUnlocked`: lists as in Step 1.
    - `testOnlyVectorSkinsHaveNoMetal`: harvest joins the vector ids.
    - `testFontsAndFeedback`: sounds `[… , "scribble"]`, harvest haptic `.faint`, harvest fonts.
    - `testArtNamesAndFolders`: folders gain `"Skins/harvest"`.
- Create test: `Tests/HarvestUnlockTests.swift`.

**Interfaces:**
- Consumes (Task 1): `SkinUnlock.achievement`, `Skins.isUnlocked(_:level:member:achievements:)`, `GameState.recordDividendSeason`, `Achievements.exDividendSkinID`. Consumes (Task 2): the `Skins/harvest/*` assets.
- Produces, for Task 4: `SkinStore.takeOffLocked(level:member:achievements:)` and `MembershipStore.achievements`.

- [ ] **Step 1: Write the tests**

```swift
// PocketDesignTests.testIsUnlocked
func open(_ level: Int, member: Bool, _ a: Set<String> = []) -> [String] { Skins.all.filter { Skins.isUnlocked($0, level: level, member: member, achievements: a) }.map(\.id) }
XCTAssertEqual(open(1, member: false), ["blackgold"])
XCTAssertEqual(open(10, member: false), ["blackgold", "voxel", "sketch"])
XCTAssertEqual(open(1, member: false, ["exDividendSkin"]), ["blackgold", "harvest"])
XCTAssertEqual(open(1, member: true), ["blackgold", "voxel", "stitch", "sketch", "harvest"])
// MotionTests
let harvest = SkinMotion.of(Skins.named("harvest"))
XCTAssertEqual(harvest.particle, .grain); XCTAssertGreaterThan(harvest.sway, 0); XCTAssertFalse(harvest.stepped); XCTAssertFalse(harvest.jitter)
XCTAssertLessThan(harvest.bobAmplitude, SkinMotion.of(Skins.named("stitch")).bobAmplitude)
XCTAssertEqual(SkinMotion.of(Skins.named("stitch")).sway, 0)
// HarvestUnlockTests (PortfolioStore on a temp URL)
func testSavingASeasonDividendUnlocks()    // saveDividend(0056, date 2026-08-10, rewardNew: true) → data.game.unlocked["exDividendSkin"] != nil; pendingReward unchanged by the season itself
func testRecordAndConfirmCount()           // record(dividend dated 2026-09-01) → unlocked; fresh store: markPaid of an existing Sept. dividend → unlocked
func testImportedBackupUnlocks()           // importBackup(bytes with a 2025-07-20 dividend) → unlocked
func testLapsedMemberKeepsAnEarnedHarvest() {
    // SkinStore wearing harvest; takeOffLocked(level: 1, member: false, achievements: ["exDividendSkin"]) == false, still harvest
    // takeOffLocked(level: 1, member: false, achievements: []) == true, now blackgold
}
func testHarvestRendersEveryComponent()    // as SkinKitTests' per-skin render, for harvest: ImageRenderer of SkinKitPreview at 390×844 non-nil
```

- [ ] **Step 2: Implement per Files.** `HeroNumber` needs no change: the vector branch draws `digit_N` on `patch` when the skin has one.

- [ ] **Step 3: Fonts.** Run `py Scripts/subset_fonts.py` so that 收成 and the new copy (here and in Task 4) are in the subset fonts, then `py Scripts/subset_fonts.py --check`. Expected: `--check` passes. Commit the changed font files under `App/Resources/Fonts` together with this task. If the performance plan has not landed yet, `--check` already covers `skins.json` names; run it anyway.

- [ ] **Step 4: Commit, push, run CI**

```bash
git add PocketCore/Sources/PocketCore/Resources/skins.json PocketCore/Sources/PocketCore/Design/Skins.swift App/Design/SkinComponents.swift App/Design/Motion.swift App/Design/SkinStore.swift App/Membership/MemberView.swift App/ETFToGoApp.swift App/Models.swift Tests/SkinArtTests.swift Tests/SkinKitTests.swift Tests/PocketReportViewTests.swift Tests/MotionTests.swift Tests/HarvestUnlockTests.swift PocketCore/Tests/PocketCoreTests/PocketDesignTests.swift App/Resources/Fonts
git commit -m "feat(skins): 收成, the fifth theme: cut paper, swaying stalks, falling grain"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. The skin matrix still has 52 shots, because harvest is not in its loop until Task 4.

---

### Task 4: 收成 on the 外觀主題 page, the wall and in CI

**Files:**
- Modify: `PocketCore/Sources/PocketCore/Design/Skins.swift`. `carouselOrder = ["voxel", "blackgold", "stitch", "sketch", "harvest"]`.
- Modify: `App/Skins/SkinCarousel.swift`:
  - `SkinStatus` gains `case needsAchievement`.
  - `init(_ skin:, current:, level:, member:, achievements: Set<String>)`. A skin with `.achievement` that is not open becomes `.needsAchievement`.
  - Copy for `.needsAchievement`: `tag` is 「7–9 月記一筆配息解鎖」 and `caption` is 「除息季」. The caption has no digits, so the "no figures on badges" check holds.
  - Copy for `.unlocked` with `.achievement`: 「會員 · 已解鎖」 when `member && !achievements.contains(id)`, else 「除息季成就 · 已解鎖」. `.wearing` stays 「使用中」.
  - The button for `.needsAchievement` is 「看成就」 (`skin-apply`, `primary: false`). It calls `navigation.open(.achievements)`.
  - `Skin.pitch` gains `case "harvest": "剪紙稻穗配米白紙底，風一吹就輕輕擺動。"`. The spec leaves this sentence open, so it is flagged for the owner's review.
  - Both `SkinStatus(...)` call sites pass `Set((store.data.game?.unlocked ?? [:]).keys)`.
- Modify: `UITests/ETFToGoUITests.swift`:
  - Add `"harvest"` to the five per-skin loops at today's lines 147, 213, 308, 327 and 396, and to the badge loops in `testSkinCarousel` and `testCarouselShowsNoNumbers`.
  - Add the new UI tests below.
- Modify: `.github/workflows/native-ui.yml`:
  - Every `for SKIN in blackgold voxel stitch sketch` loop becomes `… sketch harvest`. That covers the skin matrix, the skin kit, and the dex-reveal and widget loops where they exist.
  - The matrix count becomes 65: the `52` in the step's comment, in `captured $COUNT of 52`, in the `-ne 52` check and in the error text. The step is renamed "Capture five skins × thirteen screens", and its `timeout-minutes` goes from 20 to 25.
- Modify: `Scripts/contact_sheet.py`. `SKINS` appends `("harvest", "收成", "SKN 005")`.
- Modify: `PocketCore/Tests/PocketCoreTests/PocketDesignTests.swift`. In `testFiveSkinsInOrder`, `carouselOrder` becomes `["voxel", "blackgold", "stitch", "sketch", "harvest"]`. No app test asserts the order.
- Note for the screenshots: every CI shot launched with `--demo-pocket` (the whole skin matrix) now has 收成 unlocked, through last year's July and August sample dividends. That is expected. The matrix `achievements` shot shows 除息季限定外觀主題 as unlocked.

**Interfaces:**
- Consumes (Task 3): `takeOffLocked(level:member:achievements:)`, `MembershipStore.achievements`, the harvest skin.

- [ ] **Step 1: Write the tests**

```swift
// Tests/SkinStatusTests.swift (new)
func testHarvestStatus() {
    let h = Skins.named("harvest")
    XCTAssertEqual(SkinStatus(h, current: "blackgold", level: 40, member: false, achievements: []), .needsAchievement)
    XCTAssertEqual(SkinStatus.needsAchievement.tag(h, level: 40, member: false), "7–9 月記一筆配息解鎖")
    XCTAssertEqual(SkinStatus.needsAchievement.caption, "除息季")
    XCTAssertEqual(SkinStatus(h, current: "blackgold", level: 1, member: false, achievements: ["exDividendSkin"]), .unlocked)
    XCTAssertEqual(SkinStatus.unlocked.tag(h, level: 1, member: false, achievements: ["exDividendSkin"]), "除息季成就 · 已解鎖")
    XCTAssertEqual(SkinStatus.unlocked.tag(h, level: 1, member: true, achievements: []), "會員 · 已解鎖")
}
// UITests
func testHarvestLockedShowsTheSeason() {
    // launch ["--demo-level", "7", "--open", "skins"]; tap skin-badge-harvest
    // skin-status label "7–9 月記一筆配息解鎖"; skin-apply label "看成就"; no element label or value contains "即將推出"
    // tap skin-apply → achievement-exDividendSkin exists (5 s)
}
func testHarvestOpenAfterASeasonDividend() {
    // launch ["--demo-level", "7", "--demo-pocket", "--open", "skins"]. --demo-pocket saves last year's July and August
    // sample dividends through saveDividend (DemoArguments.lastYearSample), so 收成 is always open with it
    // tap skin-badge-harvest → skin-status contains "除息季成就 · 已解鎖"; tap skin-apply "換上這套" → lobby; pixel at (0.5, 0.15) is 0xF5EEDC
}
```

  `SkinStatus.tag` gains the `achievements:` parameter. Its only caller is the carousel.

- [ ] **Step 2: Implement per Files.**

- [ ] **Step 3: Commit, push, run CI**

```bash
git add PocketCore/Sources/PocketCore/Design/Skins.swift App/Skins/SkinCarousel.swift UITests/ETFToGoUITests.swift .github/workflows/native-ui.yml Scripts/contact_sheet.py Tests/SkinStatusTests.swift PocketCore/Tests/PocketCoreTests/PocketDesignTests.swift
git commit -m "feat(skins): 收成 on the theme page (7–9 月記一筆配息解鎖), the wall and every per-skin check"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected:
- All three jobs are green.
- `ETFToGo-skin-matrix` holds 65 shots, and its contact sheet has a fifth row 「收成 · SKN 005」.
- `skinkit-harvest.png` is among the screens.
- The 成就 wall shows 除息季限定外觀主題 at 0 / 1.
