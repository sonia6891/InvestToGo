# Living Lobby Motion and New Experience Curve Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the whole app feel like a game: a lobby that is alive at rest, juicy feedback on every tap, rewards replayed in the lobby (coins fly, XP bar fills, LEVEL×UP when it fills), staggered screen entrances, and a front-loaded experience curve.

**Architecture:** Pure rules (curve, lobby replay) live in PocketCore and are unit-tested there. A small SwiftUI motion kit in `App/Design/Motion.swift` (per-skin motion parameters, an "ambient allowed" gate, a pressable button style, a stagger modifier, an ambient bob modifier, particles) is consumed by the lobby, the LEVEL×UP view and the feature screens. RootView stops presenting LEVEL×UP on its own and only presents it when the lobby asks.

**Tech Stack:** SwiftUI (iOS 18 APIs already in use: `matchedTransitionSource`, `TimelineView`, `PhaseAnimator`, `keyframeAnimator`), XCTest, XCUITest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-living-lobby-motion-design.md` (Traditional Chinese; section numbers below refer to it).

## Global Constraints

- No new libraries or packages (no Lottie, Rive, SpriteKit scenes); no new RealityKit scene in the lobby (spec §3, §6).
- No new or split skin art: signature moves are whole-image motion plus code-drawn glints/coins (spec §5.1, §7).
- XP amounts per event and monthly caps are unchanged: monthlyDCA 100, questDone 40, firstDexCard 30, dividendLogged 20, reconciled 20, dex 3/month, dividend 3/month (spec §2).
- Curve: LV.1→2 needs 100, →3 150, →4 200, →5 250, then 300 per level forever; cumulative LV.2 100, LV.3 250, LV.4 450, LV.5 700, LV.6 1000, LV.7 1300, LV.10 2200 (spec §4).
- Reduce Motion (`@Environment(\.motionReduced)`, which already includes `MotionPreference.forced`): no movement, scale, particles or glints — fades only; numbers show final values; LEVEL×UP still appears with a fade (spec §6).
- Low Power Mode: ambient (at-rest) motion off; tap feedback, replay and LEVEL×UP unchanged (spec §6).
- `--ui-testing`: ambient motion always off; opening and replay jump to their final state at once (spec §6). Tap feedback may stay.
- Ambient motion runs only while the lobby is on screen and the scene is `.active` (spec §6).
- Never reward or animate price movement; only habits (spec §2 反目標).
- No animation delays navigation or blocks a tap; a tap during replay jumps to the final state (spec §5.3, §6).
- Only one "big event" at a time: replay (ticks → coins → +XP → bar) and LEVEL×UP never overlap (spec §2).
- Decorative motion views are `accessibilityHidden(true)`; every existing accessibility identifier keeps its name (UI tests and store screenshots depend on them).
- No network changes.
- Copy is Traditional Chinese (Taiwan).
- Commits: never `git add -A` (an untracked, locally ignored `marketing/` folder belongs to other work); stage named paths.
- Verification is CI-only (no local Swift toolchain): push `claude/living-lobby` and run `gh workflow run native-ui.yml --ref claude/living-lobby`; jobs core, simulator (unit + UI + Release compile + store-screens), skin-matrix must be green.

## Review Focus

1. Restoring a backup on the same phone (stored lobby snapshot exists, xp/coins jump) → no replay; the numbers simply show (Task 4 test `testRestoreResetsShownSnapshot`).
2. Month rollover: snapshot from last month with 3 quests done, now a new month with 0 → no ticks, no negative deltas (Task 1 test `testReplayAcrossMonthHasNoTicks`).
3. Tapping an object during the opening or the replay → navigation happens at once, LEVEL×UP is not shown over the feature screen, and it shows on the next lobby visit (Task 4 UI test `testLevelUpWaitsForLobby`).
4. Skin switch while in the lobby (RootView rebuilds the stack via `.id(skins.skin.id)`) → no second replay (Task 1 test `testEqualSnapshotsHaveNoReplay`; Task 4 saves the snapshot when the replay starts).
5. One gain that crosses two levels → one LEVEL×UP showing the highest level, bar fills once (Task 1 test `testReplayCrossingTwoLevels`).

---

### Task 1: New experience curve and the lobby replay rules (PocketCore)

**Files:**
- Modify: `PocketCore/Sources/PocketCore/Game/GameRules.swift`
- Create: `PocketCore/Sources/PocketCore/Game/LobbyReplay.swift`
- Modify: `App/Lobby/DemoArguments.swift` (`--demo-level`, the `--demo-store` LV.7 total)
- Modify tests: `PocketCore/Tests/PocketCoreTests/GameStateTests.swift`, `Tests/LobbyTests.swift`, `Tests/StoreDemoTests.swift`, `Tests/GameFlowTests.swift` (any use of `xpPerLevel` or old thresholds), `UITests/ETFToGoUITests.swift` (`testLevelUpShowsOnce` numbers only)
- Create test: `PocketCore/Tests/PocketCoreTests/LobbyReplayTests.swift`

**Interfaces:**
- Produces:
  - `GameRules.xpToReach(level: Int) -> Int` (level ≤ 1 → 0; 2 → 100; 3 → 250; 4 → 450; 5 → 700; n ≥ 5 → 700 + (n − 5) × 300).
  - `GameRules.level(xp:) -> Int` and `GameRules.progress(xp:) -> (into: Int, needed: Int)` keep their signatures with the new table. `GameRules.xpPerLevel` is removed.
  - `struct LobbySnapshot: Codable, Equatable { var xp: Int; var coins: Int; var month: String; var quests: Set<String> }` with `static func of(_ game: GameState, now: Date) -> LobbySnapshot` (month = `YearMonth(now).key`, quests = ids of this month's lobby quests that `game.isDone` in that month, using the same `Quests.forMonth(_, habit: game.habit ?? .dca, isNewbie: game.isNewbie)` the quest card uses).
  - `struct LobbyReplay: Equatable { var newQuests: [String]; var coinsFrom: Int; var coinsTo: Int; var xpFrom: Int; var xpTo: Int; var levelFrom: Int; var levelTo: Int; var crossesLevel: Bool { levelTo > levelFrom } }` with `static func between(shown: LobbySnapshot?, now: LobbySnapshot) -> LobbyReplay?`.
  - Rules of `between`: nil when `shown` is nil; nil when `now.xp < shown.xp` or `now.coins < shown.coins`; nil when nothing grew and no new quest; `newQuests` only when `shown.month == now.month` (ids in `now.quests` not in `shown.quests`, in the quest card's order), otherwise `[]`; `levelFrom/To` from `GameRules.level(xp:)`.

- [ ] **Step 1: Update `GameStateTests` curve assertions and write `LobbyReplayTests`**

```swift
// GameStateTests — replaces the 300-per-level assertions
XCTAssertEqual(GameRules.level(xp: 0), 1); XCTAssertEqual(GameRules.level(xp: 99), 1)
XCTAssertEqual(GameRules.level(xp: 100), 2); XCTAssertEqual(GameRules.level(xp: 249), 2)
XCTAssertEqual(GameRules.level(xp: 250), 3); XCTAssertEqual(GameRules.level(xp: 700), 5)
XCTAssertEqual(GameRules.level(xp: 2200), 10); XCTAssertEqual(GameRules.level(xp: 2499), 10); XCTAssertEqual(GameRules.level(xp: 2500), 11)
XCTAssertEqual(GameRules.xpToReach(level: 7), 1300)
XCTAssertTrue(GameRules.progress(xp: 250) == (0, 200)); XCTAssertTrue(GameRules.progress(xp: 449) == (199, 200))
XCTAssertTrue(GameRules.progress(xp: 1000) == (0, 300))
// testOldSaveKeepsXPAndCelebratesOnce: a decoded game with xp 900 and celebratedLevel 4 → level 5, levelUpDue == 5; after celebrate(5) levelUpDue == nil

// LobbyReplayTests
func testNoSnapshotNoReplay()            // between(shown: nil, now:) == nil
func testEqualSnapshotsHaveNoReplay()    // same snapshot → nil
func testGainReplays()                   // shown xp 260 coins 260, now 280/280 → xpFrom 260, xpTo 280, levelFrom 3, levelTo 3, !crossesLevel
func testLowerNumbersNoReplay()          // now.xp < shown.xp → nil (restore from an older backup)
func testNewQuestTicks()                 // same month, shown quests {a}, now {a,b} → newQuests == ["b"]
func testReplayAcrossMonthHasNoTicks()   // shown month "2026-10" quests {a,b,c}, now "2026-11" {} with more xp → newQuests == [], replay non-nil
func testReplayCrossingTwoLevels()       // xpFrom 90 → xpTo 300: levelFrom 1, levelTo 3, crossesLevel
func testSnapshotOfGame()                // LobbySnapshot.of a game with two quests done this month → those two ids, xp/coins copied
```

- [ ] **Step 2: Implement `xpToReach`, the new `level`/`progress`, `LobbySnapshot`, `LobbyReplay`; remove `xpPerLevel`; update `DemoArguments` (`--demo-level n` → `GameRules.xpToReach(level: n)`; `--demo-store` total → `xpToReach(level: 7) + 3/5 of that level's `needed``) and every other caller and test the compiler names.**

- [ ] **Step 3: `testLevelUpShowsOnce` numbers only:** launch with `--demo-xp 440`, initial value `"440 經驗"`, after the +20 dividend the level is `"LV.4"` and the lobby value `"460 經驗"`. (Timing change comes in Task 4.)

- [ ] **Step 4: Commit and push; run CI**

```bash
git add PocketCore/Sources/PocketCore/Game/GameRules.swift PocketCore/Sources/PocketCore/Game/LobbyReplay.swift PocketCore/Tests/PocketCoreTests/GameStateTests.swift PocketCore/Tests/PocketCoreTests/LobbyReplayTests.swift App/Lobby/DemoArguments.swift Tests/LobbyTests.swift Tests/StoreDemoTests.swift Tests/GameFlowTests.swift UITests/ETFToGoUITests.swift
git commit -m "feat(game): front-loaded experience curve and lobby replay rules"
git push -u origin claude/living-lobby && gh workflow run native-ui.yml --ref claude/living-lobby
```
Expected: core, simulator, skin-matrix green.

---

### Task 2: Motion kit

**Files:**
- Create: `App/Design/Motion.swift`
- Create test: `Tests/MotionTests.swift`
- Modify: `ETFToGo.xcodeproj/project.pbxproj` only if new files are not picked up automatically (check how existing files in `App/Design` are registered; follow that).

**Interfaces:**
- Produces:
  - `struct SkinMotion: Equatable { var bounce: Double; var stepped: Bool; var stepsPerSecond: Double; var bobAmplitude: CGFloat; var particle: MotionParticle; var jitter: Bool; static func of(_ skin: Skin) -> SkinMotion }` — by `skin.id`: `"blackgold"` smooth (stepped false, jitter false, particle `.dust`), `"voxel"` stepped true with `stepsPerSecond` 8 and particle `.square`, `"stitch"` the bounciest springs, particle `.dot`, `"sketch"` jitter true, particle `.stroke`; any other id → blackgold's values.
  - `enum MotionParticle { case dust, square, dot, stroke }`
  - `enum AmbientMotion { static func allowed(reduceMotion: Bool, lowPower: Bool, uiTesting: Bool, onScreen: Bool, active: Bool) -> Bool }` — true only when all of: !reduceMotion, !lowPower, !uiTesting, onScreen, active.
  - `final class PowerState: ObservableObject { static let shared; @Published private(set) var lowPower: Bool }` updated from `NSNotification.Name.NSProcessInfoPowerStateDidChange`.
  - `struct PressableStyle: ButtonStyle` — pressed: squash scale (≈1.12 × 0.88) with the skin's spring; reduce motion: opacity 0.7 only; never changes the label's accessibility.
  - `extension View { func enterStagger(_ index: Int) -> some View }` — on first appear, offset y ≈ 14 + opacity 0 → rest, delay `index × 0.05 s`, total ≤ 0.4 s (indexes above 7 use 7's delay); reduce motion: opacity only; `--ui-testing`: no effect.
  - `extension View { func ambientBob(phase: Double, enabled: Bool) -> some View }` — 3 s up/down cycle of `SkinMotion.bobAmplitude` (≈6 pt), `phase` 0…1 offsets the cycle; voxel quantizes time to `stepsPerSecond`; sketch adds a small rotation/offset change every 0.25 s; disabled → identity. Built on `TimelineView(.animation(paused: !enabled))`.
  - `struct AmbientParticles: View { var enabled: Bool }` — a `Canvas` in a paused-when-disabled `TimelineView` drawing ≤ 14 particles of the skin's `MotionParticle` rising and fading; `accessibilityHidden(true)`.

- [ ] **Step 1: Write `MotionTests`**

```swift
func testAmbientAllowedOnlyWhenEverythingPermits() // true for (false,false,false,true,true); false when any single flag flips
func testSkinMotionPerSkin()   // voxel.stepped && voxel.stepsPerSecond == 8; sketch.jitter; !blackgold.stepped; of(unknown id) == of(blackgold)
```
- [ ] **Step 2: Implement `App/Design/Motion.swift`.**
- [ ] **Step 3: Commit, push, CI green.** `git commit -m "feat(design): motion kit — skin motion, ambient gate, pressable, stagger, particles"`

---

### Task 3: The living lobby

**Files:**
- Modify: `App/Lobby/LobbyView.swift`, `App/Lobby/HeroNumber.swift`, the `SkinDecor` view (find it with grep), `App/ETFToGoApp.swift` only if the lobby needs scene phase passed down
- Test: `Tests/LobbyTests.swift` (pure helpers), `UITests/ETFToGoUITests.swift` (existing lobby tests must stay green)

**Interfaces:**
- Consumes: Task 2's `SkinMotion`, `AmbientMotion.allowed`, `PowerState`, `PressableStyle`, `ambientBob`, `AmbientParticles`.
- Produces: `enum LobbySignature { case swing, flip, hop, blink; static func of(_ feature: Feature) -> LobbySignature }` (find → swing, dividends → flip, pocket → hop, tools → blink) and `static func phase(_ feature: Feature) -> Double` (find 0, dividends 0.25, pocket 0.5, tools 0.75).

What to build (spec §5.1, §5.2 first bullet):
- The lobby computes one `ambient` Bool from `AmbientMotion.allowed(...)` with `onScreen` from `onAppear`/`onDisappear` and `active` from `scenePhase`.
- Each entry: `ambientBob(phase: LobbySignature.phase(feature), enabled: ambient)` on its `SkinImage`; every 4–7 s its signature move (whole-image swing ±8°, a glint drawn over the image's upper part for flip, a small code-drawn coin hopping out of the top for hop, a small light square over the image for blink).
- Entry buttons use `PressableStyle` plus a one-shot ring burst and `ConfirmFeedback.confirm(skin)`; navigation still happens in the same tap.
- `HeroNumber`: gentle float and an occasional diagonal shine when `ambient`; `SkinDecor` drifts slowly; `AmbientParticles(enabled: ambient)` behind the numeral; the XP capsule gets a moving highlight; the quest card's 「+N XP」 breathes.
- Opening (first lobby appearance after launch or after returning from background): entries pop in staggered, the numeral drops in, within 0.7 s; skipped (final state at once) with reduce motion or `--ui-testing`.

- [ ] **Step 1: Test** `testLobbySignatures()` — the four mappings and phases above.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit, push, CI green (existing UI tests, skin-matrix lobby pictures unchanged in layout).** `git commit -m "feat(lobby): the lobby is alive at rest and answers every tap"`

---

### Task 4: Replay in the lobby and LEVEL×UP when the bar fills

**Files:**
- Create: `App/Lobby/LobbyReplayPlayer.swift` (the view-side player and `LobbyShownStore`)
- Modify: `App/Lobby/LobbyView.swift`, `App/ETFToGoApp.swift` (RootView LEVEL×UP trigger), `App/Models.swift` (`importBackup` resets the shown snapshot), `App/Lobby/Feature.swift` or the lobby navigation environment (remember the feature last returned from)
- Tests: `Tests/LobbyReplayPlayerTests.swift`, `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 1's `LobbySnapshot`, `LobbyReplay.between`; Task 2's kit; Task 3's entries.
- Produces:
  - `struct LobbyShownStore { init(defaults: UserDefaults = .standard); func load() -> LobbySnapshot?; func save(_ s: LobbySnapshot); func reset() }` — key `"lobby.shownSnapshot"`, JSON.
  - `EnvironmentValues.celebrateIfDue: () -> Void` set by RootView; it presents LEVEL×UP only when `path.isEmpty`, `levelUp == nil` and `store.data.game?.levelUpDue != nil`.
  - `EnvironmentValues.returningFrom: Feature?` — the feature the user last left to come back to the lobby (nil at launch).

Behaviour (spec §5.3, §5.4):
- On lobby appear: `now = LobbySnapshot.of(game, now:)`; `replay = LobbyReplay.between(shown: store.load(), now:)`; **save `now` immediately**; if replay is nil → call `celebrateIfDue()` and stop.
- Otherwise play in order, total ≤ 2 s: new quest ticks (pop + small confetti, count 「2/3 → 3/3」) → coins fly from `returningFrom`'s entry (or from the numeral when nil) to the coin counter while the counter counts `coinsFrom → coinsTo` with `SoundFX.tick`/`coin` → 「+N XP」 floats → the XP bar moves from `progress(xpFrom)` to `progress(xpTo)`; when `crossesLevel`, it fills to full, flashes, then calls `celebrateIfDue()`.
- A tap anywhere during the replay cancels it to the final state; the tap's navigation proceeds; LEVEL×UP is not shown (path not empty) and waits for the next lobby appearance.
- Reduce motion or `--ui-testing`: no flying/counting; final numbers at once; then `celebrateIfDue()` immediately.
- RootView: remove `.task(id: store.data.game?.levelUpDue) { await celebrateWhenDue() }` presenting on any screen; keep `accept(_:)`; LEVEL×UP comes only from `celebrateIfDue()`. Keep the wait for a pending `RewardToast` (`store.pendingReward`) before presenting.
- `importBackup` success → `LobbyShownStore().reset()` (so a restore shows numbers without replay; spec §5.3).
- Fresh install: `load()` is nil → no replay; the snapshot is saved.

- [ ] **Step 1: Unit tests**

```swift
func testShownStoreRoundTrip()          // save then load returns the same snapshot; reset → nil (use a UserDefaults(suiteName:) instance)
func testRestoreResetsShownSnapshot()   // after a successful importBackup, LobbyShownStore().load() == nil
```
- [ ] **Step 2: UI tests** — change `testLevelUpShowsOnce`: after saving the dividend, the toast appears, then `XCTAssertFalse(level.waitForExistence(timeout: 4), "Not over the dividends screen")`; tap `bar-lobby`; `XCTAssertTrue(level.waitForExistence(timeout: 10))`, label `"LV.4"`; capture `"level-up"`; accept; the rest as it is. Add `testLevelUpWaitsForLobby`: `--demo-xp 440 --demo-held`, log a dividend, tap `bar-lobby`, immediately tap `lobby-find` (if LEVEL×UP is already up, the test fails on `lobby-find` not hittable — so assert `app.buttons["lobby-find"].waitForExistence(timeout: 5)` first and tap), assert `level` does not exist on 找 ETF for 3 s, tap `bar-lobby`, assert `level` appears.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Commit, push, CI green (store-screens still produce `level-up` and lobby pictures).** `git commit -m "feat(lobby): rewards replay in the lobby; LEVEL×UP when the bar fills"`

---

### Task 5: A livelier LEVEL×UP

**Files:**
- Modify: `App/Game/LevelUpView.swift`
- Test: `Tests/LobbyTests.swift` or a new `Tests/LevelUpTests.swift`

**Interfaces:**
- Consumes: Task 2's kit, existing `BurstView`, `ConfirmFeedback`, `SoundFX`.
- Produces: `LevelUpMoment` gains `let from: Int` (the previous celebrated level); `LevelUp.moment(_:level:now:)` fills it from `game.celebratedLevel`.

Behaviour (spec §5.4): the level numeral rolls from `from` to `level`; rays and a coin burst behind it; unlocked skins/achievements (existing `rewards`) appear one by one; a heavy haptic and the skin's sound once. Reduce motion: everything fades in, final numbers. Identifiers `levelup-level` (label `"LV.<level>"` at rest), `LEVEL×UP`, `levelup-share`, `levelup-accept` unchanged; it still closes only on 收下.

- [ ] **Step 1: Test** `testMomentRemembersPreviousLevel()` — a game with `celebratedLevel` 3 crossing to 5 → `moment.from == 3`, `moment.level == 5`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit, push, CI green.** `git commit -m "feat(game): LEVEL×UP rolls the level and reveals what it unlocked"`

---

### Task 6: Screens enter in sequence; main buttons press; the object bounces on return

**Files:**
- Modify: the root view of each feature (find with grep from `RouteView` / `Feature` in `App/HomeScreens.swift`: 找 ETF, 配息, 口袋, 工具, 成就), the main-action buttons there, `App/Lobby/LobbyView.swift`
- Test: UI tests stay green; no new unit test needed beyond Task 2's

**Interfaces:**
- Consumes: `enterStagger`, `PressableStyle`, `returningFrom`.

Behaviour (spec §5.2 second bullet, §5.5): the top-level blocks of each feature root (title, first cards, first rows) get `.enterStagger(0...n)`; main-action buttons (at least `dividends-log`, `save-dividend`, the combo 開始試算 button, 記一筆定投 if present) use `PressableStyle`; list rows do not. Back in the lobby, the entry for `returningFrom` gives one small bounce.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Commit, push, CI green including store-screens (pictures must be at rest: under `--ui-testing` the stagger has no effect).** `git commit -m "feat(ui): screens enter in sequence and main buttons press"`

---

### Task 7: Final check on device-facing behaviour

**Files:** none new.

- [ ] **Step 1:** Download the CI artifacts (`ETFToGo-screens`, `ETFToGo-store-screens`, skin-matrix) and look at the lobby, level-up and four-skin lobby pictures: nothing overlapping, numbers final.
- [ ] **Step 2:** Confirm by reading the code that every ambient animation is gated by `AmbientMotion.allowed` and every decorative view is `accessibilityHidden`.
