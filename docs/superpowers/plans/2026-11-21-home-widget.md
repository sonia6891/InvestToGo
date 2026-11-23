# Home Screen Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 「連續定投」 home-screen widget in two sizes. The small one shows the DCA streak. The medium one adds this month's three quests. A tap opens the app on the lobby. The widget never shows an amount, never reads the records and never goes online.

**Architecture:**
- After every save, on every return to the foreground and on every skin change, the app writes a small `widget.json` into the App Group container. It holds no amounts.
- A WidgetKit extension, `ETFToGoWidget`, compiles the PocketCore sources, exactly as the app does. It reads only that file.
- When the Taipei month rolls over, the extension recomputes the streak and resets the quests with the same `GameRules` and `Quests` code.
- Signing: production builds sign through `Scripts/asc_signing.py`. It gains a second profile for the extension. The App Group itself can only be created on developer.apple.com, which the controller does in Task 1.

**Tech Stack:** WidgetKit, SwiftUI, XcodeGen, Python 3 (`unittest`, `cryptography`), GitHub Actions. No new packages.

**Spec:** `docs/superpowers/specs/2026-11-21-habit-loop-and-polish-design.md` (Traditional Chinese, binding). This plan is delivery item §12.4 and implements §5, with rulings §10.4, §10.5, §10.6 and §10.9.

## Global Constraints

- All copy is Traditional Chinese (Taiwan usage). Say 「外觀主題」, never 「皮膚」 (§9).
- No new third-party packages (§9).
- The widget makes no network requests (§5, §9).
- The widget never shows an amount: not market value, not profit or loss, not a holding, and not the planned monthly amount either (§1, §10.9). `widget.json` holds no amount field; Task 2 has a test that pins the exact key set.
- Ids (§10.6, which overrides the literal `group.tw.sonia.etftogo` in §5):
  - the widget's bundle id is the main app's id + `.widget`;
  - the App Group is `group.` + the main app's id;
  - the production main id is the CI variable `ETF_BUNDLE_ID`, not the project's `tw.sonia.etftogo.uireview`.
  - In the project these are build settings: `ETF_APP_BUNDLE_ID`, which defaults to `tw.sonia.etftogo.uireview`, and `APP_GROUP_ID = group.$(ETF_APP_BUNDLE_ID)`.
- The streak formula is PocketCore's `GameRules`/`GameState.streak(now:)`, compiled into the extension from the same files (§10.5). Quest titles carry no amounts (§10.5).
- Quest ticks and the widget are derived from the current records on every save and every return to the foreground (§10.4). The 「本月定投一次」 tick uses `GameState.isDone(_:in:records:)` from the quick-DCA plan.
- Fonts: system fonts only, with the skin's colors. No skin fonts are bundled into the extension (§5).
- File protection of `widget.json`: `.completeFileProtectionUntilFirstUserAuthentication` (§5).
- The timeline holds one entry now and one at the next Taipei month start (§5). `GameRules.taipei` is the calendar.
- A tap opens the app on the lobby (§5).
- Until the developer-portal work in Task 1 is done, CI verifies only the unsigned simulator build (`CODE_SIGNING_ALLOWED=NO`) (§10.6). The simulator CI keeps using `tw.sonia.etftogo.uireview`.
- Do not run `testflight.yml`. The first signed run waits for the owner's go-ahead in chat. See "After the last task".
- Commits: stage named paths only. Never use `git add -A`; an untracked, locally ignored `marketing/` folder belongs to other work.
- Before Task 1: the working tree carries uncommitted 「皮膚 → 外觀主題」 copy edits in seven files. The controller commits or stashes them first.
- Verification is CI only; there is no local Swift toolchain. Every code task ends with these steps:
  1. `git add <named paths>` and `git commit`.
  2. `git push origin <branch>`, where the branch is the controller's working branch cut from `claude/living-lobby`.
  3. `gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>`.
  4. The jobs `core`, `simulator` and `skin-matrix` are green.

## Review Focus

1. **A new month with the app never opened.** On 12/1 the widget shows November's run, or 「今天開始」 if November had no DCA. The quests are December's, with nothing ticked except the newbie-only quests already done (Task 2 tests `testNewMonthResetsQuests` and `testNewMonthAfterAMissedMonth`).
2. **A streak longer than the 24 stored months.** A 30-month streak must still read 30, not 24 (Task 2 test `testLongStreakBeyondTheWindow`).
3. **A deleted DCA.** Deleting this month's only 買進 unticks 「本月定投一次」 on the widget at the next save (Task 3 test `testDeletedDCAUnticks`).
4. **A missing or damaged `widget.json`** (first install, the app never opened since the update, or a newer `version`). The widget shows the newbie state, never an empty or broken tile (Task 2 test `testUnreadableFileShowsNewbie`).
5. **Records locked while the phone is locked.** No write happens from locked or empty records, so the widget never drops to 「今天開始」 just because the phone was locked (Task 3 test `testLockedRecordsDoNotWrite`).

---

### Task 1: Developer portal and signing

The App Group can be created only on developer.apple.com; the App Store Connect API cannot create one (§10.6). The **controller** does Steps 1–2 in the browser. The implementer does Steps 3–6.

**Files:**
- Modify: `Scripts/asc_signing.py`
- Create: `Scripts/test_asc_signing.py`
- Modify: `.github/workflows/testflight.yml` (the archive step and the clean-up step)
- Modify: `.github/workflows/native-ui.yml` (the `core` job gains a step)
- Modify: `project.yml`. Project-level `settings.base` gains `ETF_APP_BUNDLE_ID: tw.sonia.etftogo.uireview` and `APP_GROUP_ID: group.$(ETF_APP_BUNDLE_ID)`. In the `ETFToGo` target, `PRODUCT_BUNDLE_IDENTIFIER` becomes `$(ETF_APP_BUNDLE_ID)` and a new `PROVISIONING_PROFILE_SPECIFIER: $(APP_PROFILE_SPECIFIER)` is added. Both specifier variables are empty by default; Automatic signing ignores them.

**Interfaces:**
- Produces, for Task 4:
  - The settings `ETF_APP_BUNDLE_ID`, `APP_GROUP_ID` and `WIDGET_PROFILE_SPECIFIER`; the widget target sets `PROVISIONING_PROFILE_SPECIFIER: $(WIDGET_PROFILE_SPECIFIER)`.
  - `$GITHUB_ENV` gains `WIDGET_PROFILE_NAME`, `WIDGET_PROFILE_UUID` and `ASC_WIDGET_PROFILE_ID`.
- New functions in `asc_signing.py`. `prepare()` calls them; the unit tests call them directly.
  - `find_bundle(identifier: str) -> tuple[str, str]` returns `(resource id, team seedId)`. If the bundle id is missing it raises `ApiError`, keeping today's message for the main id.
  - `require_app_groups(resource_id: str, identifier: str) -> None` reads `GET bundleIds/{id}/bundleIdCapabilities` and needs a `capabilityType == "APP_GROUPS"`.
  - `make_profile(bundle_resource_id: str, cert_id: str, name: str) -> tuple[str, str]` creates the `IOS_APP_STORE` profile, installs it in both provisioning folders and returns `(uuid, name)`.
  - `export_options(bundle: str, team: str, app_profile: str, widget_profile: str) -> dict`.

- [ ] **Step 1 (controller): read the production id and ask the owner**

  Run `gh variable get ETF_BUNDLE_ID --repo sonia6891/InvestToGo`; call the value `<ID>`. Tell the owner in chat exactly what Step 2 will register and change, and wait for a clear yes:
  - a new App Group `group.<ID>`;
  - a new App ID `<ID>.widget` with App Groups;
  - App Groups switched on for the existing App ID `<ID>`.

  Step 2 includes confirming Apple's warning that existing profiles for `<ID>` become invalid. That is harmless here: every TestFlight run creates its own profile. Signing in and two-factor codes are the owner's to enter.

- [ ] **Step 2 (controller): register on developer.apple.com through the owner's signed-in browser**

  Under Certificates, Identifiers & Profiles → Identifiers:
  1. **+ → App Groups.** Description `ETFToGo`, identifier `group.<ID>` → Continue → Register.
  2. **+ → App IDs → App.** Description `ETFToGo Widget`, explicit Bundle ID `<ID>.widget`, tick **App Groups** → Continue → Register. Then open it, App Groups → **Configure** → tick `group.<ID>` → Continue → Save.
  3. **Open `<ID>`.** Tick **App Groups** → **Configure** → tick `group.<ID>` → Continue → Save → confirm the "Modify App Capabilities" dialog.

  Each Register, Save and Confirm is a form submission. Do each only after the owner's yes from Step 1. Report back in chat what now exists.

- [ ] **Step 3: Write `Scripts/test_asc_signing.py`** (stdlib `unittest`)

  Before importing the module, set `RUNNER_TEMP` to a temp dir and `GITHUB_ENV` to a temp file. Replace `asc_signing.call` with a fake that records `(method, path)` and answers from a dict.

```python
def test_export_options_name_both_profiles(self):
    o = asc_signing.export_options("tw.x.app", "TEAM1", "P-app", "P-widget")
    self.assertEqual(o["provisioningProfiles"], {"tw.x.app": "P-app", "tw.x.app.widget": "P-widget"})
    self.assertEqual((o["signingStyle"], o["teamID"], o["method"]), ("manual", "TEAM1", "app-store-connect"))
def test_missing_widget_bundle_names_it(self):
    # bundleIds?…filter[identifier]=tw.x.app.widget → {"data": []}
    with self.assertRaises(asc_signing.ApiError) as e: asc_signing.find_bundle("tw.x.app.widget")
    self.assertIn("tw.x.app.widget", str(e.exception)); self.assertIn("開發者網站", str(e.exception))
def test_without_app_groups_fails(self):
    # bundleIds/B1/bundleIdCapabilities → {"data": [{"attributes": {"capabilityType": "PUSH_NOTIFICATIONS"}}]}
    with self.assertRaises(asc_signing.ApiError) as e: asc_signing.require_app_groups("B1", "tw.x.app")
    self.assertIn("App Groups", str(e.exception)); self.assertIn("group.tw.x.app", str(e.exception))
def test_with_app_groups_passes(self)  # capabilityType "APP_GROUPS" → no raise
def test_cleanup_deletes_both_profiles_then_the_certificate(self):
    # env ASC_PROFILE_ID=p1, ASC_WIDGET_PROFILE_ID=p2, ASC_CERT_ID=c1
    asc_signing.cleanup()
    self.assertEqual(calls, [("DELETE", "profiles/p1"), ("DELETE", "profiles/p2"), ("DELETE", "certificates/c1")])
```

- [ ] **Step 4: Change `asc_signing.py`**

  `prepare()` keeps its order and its cloud fallback.
  - First it runs `find_bundle` for `bundle` and for `bundle + ".widget"`, then `require_app_groups` for both. It does all this before creating a certificate, so a missing portal step costs nothing and also stops the cloud path.
  - Error copy:
    - missing widget id: 「App Store Connect 找不到小工具的 Bundle ID {widget}；請先在開發者網站註冊它並開啟 App Groups（group.{bundle}）。」
    - capability off: 「Bundle ID {identifier} 沒有開啟 App Groups；請在開發者網站開啟並指定 group.{bundle}。」, where `{bundle}` is the main id.
  - It creates two profiles with the same certificate:
    - the app's, named `ETFToGo TestFlight <run id>`;
    - the widget's, named `ETFToGo Widget TestFlight <run id>`.
  - Each profile's id goes to `$GITHUB_ENV` as soon as it exists (`ASC_PROFILE_ID`, `ASC_WIDGET_PROFILE_ID`), so `cleanup` can always delete it.
  - It writes `WIDGET_PROFILE_NAME` and `WIDGET_PROFILE_UUID` beside today's values. `ExportOptions.plist` comes from `export_options`.
  - `cleanup()` deletes `profiles/ASC_PROFILE_ID`, then `profiles/ASC_WIDGET_PROFILE_ID`, then `certificates/ASC_CERT_ID`, each only when set.
  - Update the module docstring.

- [ ] **Step 5: Change the workflows**
  - `testflight.yml`, archive step, manual branch:
    - `SIGN=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Distribution" "APP_PROFILE_SPECIFIER=$PROFILE_NAME" "WIDGET_PROFILE_SPECIFIER=$WIDGET_PROFILE_NAME")`.
    - `PRODUCT_BUNDLE_IDENTIFIER="$ETF_BUNDLE_ID"` is replaced by `ETF_APP_BUNDLE_ID="$ETF_BUNDLE_ID"`. A command-line `PRODUCT_BUNDLE_IDENTIFIER` would give the extension the app's id.
  - `testflight.yml`, clean-up step: also remove `$WIDGET_PROFILE_UUID.mobileprovision` from both folders.
  - `native-ui.yml`, `core` job: add a step "Test the signing script" that runs `python3 -m venv "$RUNNER_TEMP/asc"`, `"$RUNNER_TEMP/asc/bin/pip" install --quiet cryptography` (as `testflight.yml` does) and `"$RUNNER_TEMP/asc/bin/python" -m unittest discover -s Scripts -p 'test_asc_signing.py' -v`.

- [ ] **Step 6: Commit, push, run CI**

```bash
git add Scripts/asc_signing.py Scripts/test_asc_signing.py .github/workflows/testflight.yml .github/workflows/native-ui.yml project.yml
git commit -m "build(signing): a second App Store profile for the widget; both ids need App Groups"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: the `core` job shows 5 signing tests passing, and all three jobs are green. The simulator app's bundle id is still `tw.sonia.etftogo.uireview`.

---

### Task 2: `WidgetSnapshot` in PocketCore

**Files:**
- Create: `PocketCore/Sources/PocketCore/Game/WidgetSnapshot.swift`
- Create test: `PocketCore/Tests/PocketCoreTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Consumes (quick-DCA plan, already merged): `GameState.isDone(_ quest: Quest, in: YearMonth, records: Portfolio) -> Bool`.
- Produces:
  - `struct WidgetQuest: Codable, Equatable { var id: String; var title: String; var done: Bool }`
  - `struct WidgetSnapshot: Codable, Equatable` with:
    - `static let version = 1`;
    - fields `version: Int`, `writtenAt: Date`, `month: String` (`YearMonth.key`), `streak: Int`, `longestStreak: Int`, `isNewbie: Bool`, `habit: Habit`, `dcaMonths: [String]` (the newest 24 keys, ascending), `quests: [WidgetQuest]` and `skinID: String`.
    - **Flagged deviation:** `habit` and the quest `id`s are not in §5's list. They are needed to build next month's quests when the month rolls over, and neither is an amount.
    - `static func of(_ p: Portfolio, skinID: String, now: Date) -> WidgetSnapshot`. It uses `p.game ?? GameState()` and `habit ?? .dca`. The quests are `Quests.forMonth(month, habit:, isNewbie:)`, ticked by `isDone(_:in:records: p)`.
    - `func display(at date: Date) -> WidgetSnapshot`, the snapshot as the widget shows it at `date`:
      - Same month as `month`: itself.
      - A later month:
        - `month` becomes the new key.
        - `streak` is `GameState` built from `dcaMonths` → `streak(now: date)`. When that run reaches the oldest stored month, the stored `streak` is used instead; no month can be added without the app writing a new file.
        - `quests` is `Quests.forMonth(new month, habit:, isNewbie:)`. Only newbie-only quests (`Quests.newbieOnly`) already done in the stored list keep `done`.
      - An earlier month (the clock went back): itself.
    - `var unchanged: WidgetSnapshot`: a copy with `writtenAt` set to `Date(timeIntervalSince1970: 0)`, so two writes can be compared.
    - `static func decode(_ data: Data) -> WidgetSnapshot?`: nil when the data does not decode or `version > WidgetSnapshot.version`.
    - `static func newbie(now: Date) -> WidgetSnapshot`: streak 0, longest 0, `isNewbie` true, `.dca`, no months, newbie quests none done, `skinID` `"blackgold"`. This is the placeholder for a missing or unreadable file.
    - `static func nextMonthStart(after date: Date) -> Date`, in `GameRules.taipei`.
  - `struct WidgetHero: Equatable { var top: String; var value: Int; var bottom: String? }` with `static func of(_ s: WidgetSnapshot) -> WidgetHero`. The copy follows §5 and the lobby (never a bare 0):
    - running: `("連續定投", streak, "個月")`;
    - broken: `("今天開始", 1, "最長紀錄 \(max(longestStreak, 1)) 個月")`;
    - newbie: `("今天開始", 1, nil)`.
  - `extension WidgetSnapshot { var questLine: String }`: 「本月任務 \(done)/\(count)」, for example 「本月任務 2/3」.

- [ ] **Step 1: Write `WidgetSnapshotTests`.** `now` is 2026-11-21 12:00 in `GameRules.taipei`.

```swift
func testOfCarriesOnlyTheAllowedKeys() {
    // Portfolio with a holding of 123456 shares at cost 9876543, a 買進 trade this month, game with a 12-month streak
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetSnapshot.of(p, skinID: "voxel", now: now))) as! [String: Any]
    XCTAssertEqual(Set(json.keys), ["version","writtenAt","month","streak","longestStreak","isNewbie","habit","dcaMonths","quests","skinID"])
    XCTAssertEqual(Set((json["quests"] as! [[String: Any]])[0].keys), ["id","title","done"])
    let text = String(decoding: try JSONEncoder().encode(WidgetSnapshot.of(p, skinID: "voxel", now: now)), as: UTF8.self)
    XCTAssertFalse(text.contains("123456")); XCTAssertFalse(text.contains("9876543"))
}
func testOfReadsStreakAndQuests() {
    // 12 months 2025-12…2026-11, longest 12, habit .dca, a 買進 dated 2026-11-05
    XCTAssertEqual(s.month, "2026-11"); XCTAssertEqual(s.streak, 12); XCTAssertEqual(s.longestStreak, 12); XCTAssertFalse(s.isNewbie)
    XCTAssertEqual(s.quests.first, WidgetQuest(id: "dcaLogged", title: "本月定投一次", done: true))
    XCTAssertEqual(s.quests.count, 3); XCTAssertEqual(s.dcaMonths.first, "2025-12"); XCTAssertEqual(s.dcaMonths.last, "2026-11")
}
func testKeepsOnlyTheNewest24Months()        // 30 months 2024-06…2026-11 → dcaMonths.count 24, first "2024-12"
func testDCATickFollowsTheRecords()          // dcaMonths has 2026-11 and questsDone has dcaLogged, but no 買進 in Nov → quests[0].done false
func testNewMonthResetsQuests() {
    // written 2026-11-21 with dcaLogged done and streak 12 → display(at: 2026-12-01 09:00 Taipei)
    XCTAssertEqual(d.month, "2026-12"); XCTAssertEqual(d.streak, 12)
    XCTAssertEqual(d.quests.map(\.id), Quests.forMonth(YearMonth(year: 2026, month: 12), habit: .dca, isNewbie: false).map(\.id))
    XCTAssertTrue(d.quests.allSatisfy { !$0.done })
}
func testNewMonthAfterAMissedMonth()        // months 2026-06…2026-10, written 2026-10-20, display 2026-12-02 → streak 0, WidgetHero top "今天開始", bottom "最長紀錄 5 個月"
func testNewbieQuestsStayDoneAcrossMonths() // newbie, firstDexCard done in Nov → display Dec: firstDexCard done true, firstPlanSet false, dcaLogged false
func testLongStreakBeyondTheWindow()        // 30-month streak written 2026-11-21 → display 2026-12-03: streak 30 (not 24)
func testSameMonthIsUnchanged()             // display(at: now + 3 days) == s
func testUnchangedIgnoresWrittenAt()        // of(p, now) and of(p, now + 60 s) differ, .unchanged equal
func testUnreadableFileShowsNewbie() {
    XCTAssertNil(WidgetSnapshot.decode(Data("{".utf8)))
    // a valid encoding with version 2 → nil
    XCTAssertEqual(WidgetHero.of(.newbie(now: now)), WidgetHero(top: "今天開始", value: 1, bottom: nil))
}
func testHeroCopy()      // running 12 → ("連續定投", 12, "個月"); broken longest 0 (not newbie) → bottom "最長紀錄 1 個月"
func testQuestLine()     // 2 of 3 done → "本月任務 2/3"
func testNextMonthStart() {
    XCTAssertEqual(WidgetSnapshot.nextMonthStart(after: now), ISO8601DateFormatter().date(from: "2026-11-30T16:00:00Z"))
    // 2026-12-31 23:59 Taipei → 2026-12-31T16:00:00Z (2027-01-01 00:00 Taipei)
}
```

- [ ] **Step 2: Implement per Interfaces.** Use `Codable` for `Habit`; it already is.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add PocketCore/Sources/PocketCore/Game/WidgetSnapshot.swift PocketCore/Tests/PocketCoreTests/WidgetSnapshotTests.swift
git commit -m "feat(widget): the amount-free snapshot the widget reads, and how it rolls into a new month"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green.

---

### Task 3: The app writes `widget.json`

**Files:**
- Create: `App/Widget/WidgetSync.swift`
- Modify: `App/Models.swift`. `PortfolioStore` gains `var onCommit: ((Portfolio) -> Void)?`, called as the last line of `commit` after `data = next`.
- Modify: `App/ETFToGoApp.swift`.
  - `init` sets `WidgetSync.shared.locked` (see Interfaces) and `store.onCommit` to `WidgetSync.shared.sync`.
  - `RootView.task(id: phase)` on `.active` calls `WidgetSync.shared.sync(store.data)`.
  - A `.task(id: skins.skin.id)` calls it with the new skin. That task also runs on first appear, which covers the first write after the update.
- Modify: `project.yml`.
  - `ETFToGo.entitlements: { path: Support/ETFToGo.entitlements, properties: { com.apple.security.application-groups: ['$(APP_GROUP_ID)'] } }`.
  - `info.properties` gains `ETFAppGroup: '$(APP_GROUP_ID)'`.
- Modify: `.gitignore`. Add `Support/*.entitlements` and `Support/ETFToGoWidget-Info.plist`; XcodeGen writes both.
- Create test: `Tests/WidgetSyncTests.swift`

**Interfaces:**
- Consumes (Task 2): `WidgetSnapshot.of`, `.unchanged`, `.decode`.
- Produces:
  - `@MainActor final class WidgetSync`:
    - `static let shared = WidgetSync(directory: WidgetSync.groupDirectory(), reload: { WidgetCenter.shared.reloadAllTimelines() }, skinID: { SkinStore.shared.skin.id }, locked: { true })`.
    - `init(directory: URL?, reload: @escaping () -> Void, skinID: @escaping () -> String, locked: @escaping () -> Bool, now: @escaping () -> Date = Date.init)`.
    - `func sync(_ p: Portfolio)` does nothing when `directory == nil` or `locked()`. Otherwise it builds `WidgetSnapshot.of(p, skinID: skinID(), now: now())`. If `.unchanged` matches the last written one (kept in memory, or read once from the file), it does nothing. Else it writes `directory/widget.json` with `[.atomic, .completeFileProtectionUntilFirstUserAuthentication]` and calls `reload()`.
    - `private(set) var writes: Int`.
    - `static func groupDirectory() -> URL?` reads `Bundle.main.object(forInfoDictionaryKey: "ETFAppGroup")` and returns `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`. It is nil on the unsigned simulator build, so CI writes nothing.
    - `static let fileName = "widget.json"`.
  - `locked` is a `var`. `shared` starts with `{ true }`, so nothing is written before the store exists. `ETFToGoApp.init` sets `WidgetSync.shared.locked = { [weak store] in store?.recordsLocked ?? true }` right after building the store. A locked store must never write a newbie snapshot over a real one.

- [ ] **Step 1: Write `WidgetSyncTests`.** Each test uses a fresh temp directory, a counting `reload` and fixed `now`/`skinID`.

```swift
func testWritesTheSnapshot()            // sync(p) → file decodes to WidgetSnapshot.of(p, skinID: "stitch", now: now); writes 1; reloads 1
func testWritesOnlyWhenChanged()        // sync(p) twice, now advanced 60 s → writes 1, reloads 1
func testSkinChangeWrites()             // sync(p); skinID → "sketch"; sync(p) → writes 2, file skinID "sketch"
func testDeletedDCAUnticks()            // p with this month's 買進 → sync → quests[0].done true; p without the trade → sync → false, writes 2
func testLockedRecordsDoNotWrite()      // locked { true } → sync → no file, writes 0, reloads 0
func testNoContainerDoesNothing()       // directory nil → sync → writes 0, reloads 0
func testFileProtectionClass()          // attributesOfItem(widget.json)[.protectionKey] is .completeUntilFirstUserAuthentication or nil (the simulator does not record it)
func testStoreCommitCallsOnCommit()     // PortfolioStore(url: temp) with onCommit capturing → `favorite("0050")` → captured once, and its `favorites` contains "0050"
```

- [ ] **Step 2: Implement per Interfaces.** `import WidgetKit` in `WidgetSync.swift` only.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Widget/WidgetSync.swift App/Models.swift App/ETFToGoApp.swift project.yml .gitignore Tests/WidgetSyncTests.swift
git commit -m "feat(widget): the app keeps widget.json in the App Group after each save, return and skin change"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. Nothing else changes in the screenshots.

---

### Task 4: The widget extension

**Files:**
- Create: `Widget/StreakWidget.swift`, which holds:
  - the `@main` `WidgetBundle`;
  - `StreakProvider: TimelineProvider`;
  - `StreakWidget`, kind `"StreakWidget"`, `.configurationDisplayName("連續定投")`, `.description("連續定投的月數與本月任務")`, `.supportedFamilies([.systemSmall, .systemMedium])`.
- Create: `WidgetShared/StreakWidgetViews.swift`, compiled into both the app and the extension: `StreakSmallView(snapshot:skin:)`, `StreakMediumView(snapshot:skin:)` and `StreakWidgetView(snapshot:skin:family:)`. It has its own `fileprivate` 0xRRGGBB → `Color`, because the app's `Color(rgb:)` lives in `SkinStore.swift`, which is not in the extension.
- Modify: `project.yml`:
  - New target `ETFToGoWidget`:
    - `type: app-extension`, `platform: iOS`;
    - sources `Widget`, `WidgetShared`, and `PocketCore/Sources/PocketCore` with `excludes: [Resources/catalog.json, Resources/annual-fees.json, Resources/official-dividends.json]`. `skins.json` stays.
    - `info: { path: Support/ETFToGoWidget-Info.plist, properties: { NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }, ETFAppGroup: '$(APP_GROUP_ID)' } }`;
    - `entitlements: { path: Support/ETFToGoWidget.entitlements, properties: { com.apple.security.application-groups: ['$(APP_GROUP_ID)'] } }`;
    - settings `PRODUCT_BUNDLE_IDENTIFIER: $(ETF_APP_BUNDLE_ID).widget`, `PROVISIONING_PROFILE_SPECIFIER: $(WIDGET_PROFILE_SPECIFIER)`, `GENERATE_INFOPLIST_FILE: YES`, `INFOPLIST_KEY_CFBundleDisplayName: 投資袋著走`, `TARGETED_DEVICE_FAMILY: '1'`, `APPLICATION_EXTENSION_API_ONLY: YES`.
  - `ETFToGo` gains `sources: WidgetShared` and `dependencies: - target: ETFToGoWidget`, which embeds it.
  - `info.properties` gains `CFBundleURLTypes: [{ CFBundleURLName: tw.sonia.etftogo, CFBundleURLSchemes: [etftogo] }]`.
- Create: `App/Widget/AppURL.swift`: `enum AppURL { static let lobby = URL(string: "etftogo://lobby")!; static func opensLobby(_ url: URL) -> Bool }`, true for scheme `etftogo` with host `lobby` only.
- Modify: `App/ETFToGoApp.swift`. `RootView` gets `.onOpenURL { if AppURL.opensLobby($0) { navigation.toLobby() } }`, using the same `toLobby` the root view already builds.
- Modify: `App/HomeScreens.swift` and `App/Design/SkinKitPreview.swift`.
  - Add `#if DEBUG case widgetPreview` to `AppRoute`; `RouteView` shows `WidgetPreview`.
  - `SkinKitLaunch` also opens it for `--open widgetPreview`.
  - `WidgetPreview` (DEBUG) shows, on the skin's page color, small and medium tiles at 158×158 and 338×158 pt with 22 pt corner radius for three states: running 12 with 2/3, broken with 「最長紀錄 5 個月」, and newbie.
  - The tiles have the ids `widget-preview-small-running`, `widget-preview-medium-running`, `widget-preview-small-broken` and `widget-preview-small-newbie`.
- Modify: `.github/workflows/native-ui.yml`.
  - In the simulator job's "Compile native app" step, assert that `ETFToGo.app/PlugIns/ETFToGoWidget.appex/Info.plist` exists, its `CFBundleIdentifier` is `tw.sonia.etftogo.uireview.widget`, and it holds no `catalog.json`.
  - In "Capture the skin kit sheet in every skin", also capture `widget-<skin>.png` with `--open widgetPreview`.
- Modify: `.github/workflows/testflight.yml`. After the archive, a python check that `Products/Applications/ETFToGo.app/PlugIns/ETFToGoWidget.appex/Info.plist` has `CFBundleIdentifier == "$ETF_BUNDLE_ID.widget"` and the same `CFBundleVersion` as the app. When `SIGNING != cloud`, `codesign -d --entitlements - --xml` on both bundles must contain `group.$ETF_BUNDLE_ID`.
- Create tests: `Tests/StreakWidgetViewTests.swift` and `Tests/AppURLTests.swift`; UI test `testWidgetPreviewStates` in `UITests/ETFToGoUITests.swift`.

**Interfaces:**
- Consumes (Task 2): `WidgetSnapshot.decode`, `.display(at:)`, `.newbie(now:)`, `.nextMonthStart(after:)`, `WidgetHero.of`, `.questLine`. Also `Skin.named(_:)` and `Skin.colors` from PocketCore.
- `StreakProvider`:
  - It reads `<group container>/widget.json` through `Bundle.main` `ETFAppGroup`. A missing container or an unreadable file means `.newbie(now:)`.
  - `getTimeline` returns two entries, `now` and `nextMonthStart(after: now)`, each with `snapshot.display(at: entryDate)`, and the policy `.after(nextMonthStart)`.
  - `placeholder` and the gallery `getSnapshot` (`context.isPreview`) show a fixed sample: running 12, quests 2/3, blackgold. Otherwise `getSnapshot` reads the file like `getTimeline`.
- Views (system fonts only):
  - Background: `skin.colors.page`, with a 6 pt `accent` band along the top edge (the skin's main color, §5). The number and text are `ink`, the captions `sub`. `accent` is never a text color: on sketch it is a 1.4:1 highlighter.
  - Small: `hero.top` (caption), `hero.value` (`.system(size: 56, weight: .bold, design: .rounded)`, `.minimumScaleFactor(0.5)`), then `hero.bottom` when not nil.
  - Medium: the small block on the left. On the right, `questLine` and three rows, each a `checkmark.circle.fill` (`ink`) or a `circle` (`sub`) with the title, `.lineLimit(1)`.
  - `.widgetURL(AppURL.lobby)`; `.containerBackground(for: .widget) { skin page color }`.
  - Accessibility label: small 「連續定投 12 個月」, broken 「今天開始，最長紀錄 5 個月」, newbie 「今天開始」. The medium adds 「，本月任務 2/3」.
  - No amount appears anywhere.

- [ ] **Step 1: Write the tests**

```swift
// StreakWidgetViewTests
func testRendersInEverySkinAndFamily()   // for Skins.all × [.systemSmall, .systemMedium]: ImageRenderer(StreakWidgetView(snapshot: sample, skin:, family:)) at 158×158 / 338×158 → non-nil
func testSpokenLabels() {
    XCTAssertEqual(StreakWidgetView.spoken(running12, family: .systemSmall), "連續定投 12 個月")
    XCTAssertEqual(StreakWidgetView.spoken(running12with2of3, family: .systemMedium), "連續定投 12 個月，本月任務 2/3")
    XCTAssertEqual(StreakWidgetView.spoken(broken5, family: .systemSmall), "今天開始，最長紀錄 5 個月")
    XCTAssertEqual(StreakWidgetView.spoken(.newbie(now: now), family: .systemSmall), "今天開始")
}
// AppURLTests
func testOnlyTheLobbyURLOpensTheLobby()  // etftogo://lobby true; etftogo://dividends false; https://lobby false
// UITests
func testWidgetPreviewStates() {
    // launch ["--ui-testing", "--reset", "--skip-onboarding", "--open", "widgetPreview"]
    // widget-preview-small-running exists (5 s); staticTexts "連續定投", "12", "個月", "本月任務 2/3", "最長紀錄 5 個月" exist; "今天開始" exists
}
```

  `static func spoken(_ s: WidgetSnapshot, family: WidgetFamily) -> String` lives on `StreakWidgetView` in the shared file.

- [ ] **Step 2: Implement per Files and Interfaces.**

- [ ] **Step 3: Commit, push, run CI**

```bash
git add Widget/StreakWidget.swift WidgetShared/StreakWidgetViews.swift App/Widget/AppURL.swift App/ETFToGoApp.swift App/HomeScreens.swift App/Design/SkinKitPreview.swift project.yml .github/workflows/native-ui.yml .github/workflows/testflight.yml Tests/StreakWidgetViewTests.swift Tests/AppURLTests.swift UITests/ETFToGoUITests.swift
git commit -m "feat(widget): 連續定投 home-screen widget, small and medium, opening the lobby"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected:
- All three jobs are green.
- The compile step logs the appex check.
- `ETFToGo-screens` holds `widget-<skin>.png` for every skin, showing the three states with no amounts.
- The Release compile (unsigned) builds the extension too.

---

## After the last task (owner's go-ahead only)

The signed path can only be proven by a TestFlight run, which uploads a build. Ask the owner in chat before `gh workflow run testflight.yml`. When the owner says yes, `prepare` takes one of two paths, and its log says which.

**Temporary certificate** (`prepare` ends with "Prepared signing for …"):
- The archive step logs the widget id `<ID>.widget` and `Verified group.<ID> in the archived ETFToGo.app` and `… ETFToGoWidget.appex`.
- The step 「Check the App Group in the exported IPA」 logs `Verified group.<ID> in the exported ETFToGo.app` and `… ETFToGoWidget.appex`, and the run summary says "Verified the exported IPA".
- `cleanup` logs the removal of two profiles and one certificate.

**Cloud signing** (the 409 path; `prepare` logs "signing in the cloud instead" and "Prepared cloud signing for …"). This is the path the account is expected to take, since the team already holds two distribution certificates:
- The archive step logs "Removed the vendor signature from Sentry", then "Signed the widget and the app ad hoc with group.<ID> for the export to carry", then the widget id and `Verified group.<ID> in the archived …` for both bundles.
- The step 「Check the App Group in the exported IPA」 logs `Verified group.<ID> in the exported ETFToGo.app` and `… ETFToGoWidget.appex`. It finds no ad hoc signature left in the app, the widget or the frameworks, `codesign --verify --deep` passes, and the run summary says "Verified the exported IPA".
- Only then does 「Upload archive to App Store Connect」 run. `cleanup` removes nothing, since no certificate or profile was created.

On either path, a missing group or a leftover ad hoc signature fails the job with `::error::` before anything is uploaded. After the build reaches TestFlight, check on a tester's phone that the widget shows the real streak, not 「今天開始」: once after a save, and again after a restart and unlock.

If `prepare` stops with one of the Task 1 messages, a portal step from Task 1 Step 2 is missing.
