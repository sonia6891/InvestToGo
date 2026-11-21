# Performance Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A smaller app that opens faster and idles cheaper. Bundled fonts drop from about 14.4 MB to under 4 MB. The black-gold and pixel theme images drop from about 9.3 MB to under 4 MB. Side files are read after the first screen. There is no live-feed loop without a Fugle key, and the lobby's 3D lighting environment is built once.

**Architecture:** Build-time work stays in the existing Python scripts. `Scripts/subset_fonts.py` gets a new character set, subsets the Latin fonts too, and gains a size gate in `--check`. `Scripts/export_skin_art.py` quantizes PNGs on export and gates on a PSNR floor. Runtime changes are small and local: `PortfolioStore` loads its three side files on demand, `LiveFeed` starts no timer without a key, and `PocketHero` caches one `EnvironmentResource`.

**Tech Stack:** Python 3 with fontTools 4.66.1 and Pillow 12.3.0 (both already pinned in CI), SwiftUI, RealityKit, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-habit-loop-and-polish-design.md` (Traditional Chinese, binding). This plan is delivery item §12.2 and implements §6, with ruling §10.7.

## Conflict found while planning (§6.1 against §6.1)

The design asks for both of these:
- a 4,000-character common list kept as insurance for user input;
- a font total under 4 MB.

They cannot both hold. Measured on 2026-11-21 against the bundled fonts:
- The app's own text plus every catalogue ETF name is 910 CJK characters. The six CJK fonts come to 3.14 MB.
- Every 1,000 more characters adds about 2.1 MB, so 4,000 more comes to 10.4 MB.
- The five Latin fonts are 1.0 MB as shipped and 0.35 MB once subset.

Ruling §10.7 settles which requirement gives way. Rare characters a person types fall back to the system font, and the coverage test only requires the app's strings and the ETF list. So **the 4 MB target is binding and the insurance list is cut to fit**: it keeps as many of the most frequent characters as stay under the gate, which is about 200.

The controller should tell the owner. Names fetched at run time, such as component-stock company names on 持股 and catalogue entries added after the build, will show some characters in the system font.

## Global Constraints

- All copy is Traditional Chinese (Taiwan usage). Say 「外觀主題」, never 「皮膚」 (§9).
- No new third-party packages: no new Swift packages, and no new Python packages beyond fontTools 4.66.1 and Pillow 12.3.0, which CI already pins (§9).
- Network requests still carry only ETF codes and dates (§9).
- Reduce Motion, Low Power Mode and `--ui-testing` follow the living-lobby rules (§9).
- Only changes that are certainly beneficial and low-risk; there are no device measurements (§6).
- All fonts are SIL OFL. Before subsetting a font, confirm its licence file in `App/Resources/Fonts/LICENSES` allows it. Keep family and PostScript names unchanged, which also leaves the OFL Reserved Font Name clause untouched (§10.7).
- The coverage test must prove that every Chinese character in the app's sources and every character of every bundled catalogue ETF name is in every Traditional-Chinese skin font (§6.1). DotGothic16 stays exempt, as today.
- Theme images: lossless optimization first, then lossy quantization only if it is needed to reach the target and is visually indistinguishable. Confirm that with a measured comparison and the CI skin-matrix screenshots (§6.2).
- Item §6.6 (ambient clocks at most 30 frames per second, and 8 per second for pixel) is already done on `claude/living-lobby`. There is no task for it here.
- Item §6.3 says the launch migration does not write when nothing changed. That is already true (`updateGame` compares before it commits). Task 3 pins it with a test.
- Commits: stage named paths only. Never use `git add -A`; an untracked, locally ignored `marketing/` folder belongs to other work.
- Before Task 1: the working tree carries uncommitted 「皮膚 → 外觀主題」 copy edits in seven files (`App/Game/LevelUpView.swift`, `App/Membership/MemberView.swift`, `App/Skins/SkinCarousel.swift`, `App/ToolsView.swift`, `PocketCore/Sources/PocketCore/Game/Achievements.swift`, `Tests/StoreDemoTests.swift`, `UITests/ETFToGoUITests.swift`). The controller commits or stashes them first. Those strings feed the font character set.
- Verification is CI only; there is no local Swift toolchain. Python scripts can and should be run locally on Windows (Python 3.12, fontTools and Pillow are installed). Every task ends with these steps:
  1. `git add <named paths>` and `git commit`.
  2. `git push origin <branch>`, where the branch is the controller's working branch cut from `claude/living-lobby`.
  3. `gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>`.
  4. The jobs `core`, `simulator` and `skin-matrix` are green.

## Review Focus

1. **A skin's own name or a new UI string uses a character outside the old set.** For example, 收成 from the harvest plan, or any copy added after this pass. `--check` must fail with the missing characters, not ship tofu. Task 1 keeps `app_characters()` scanning `App/**`, `PocketCore/**` and `skins.json`, and the check runs in CI `core`.
2. **Sketch's variable Caveat font after subsetting.** Its bold instance (`bigBold`) must still render. Task 1 keeps `gvar`/`fvar`, and `SkinArtTests.testFontsAreRegistered` plus the skin-matrix sketch shots confirm it.
3. **Semi-transparent edges of the 3D renders after quantization.** Haloing over the dark page is the likely failure. Task 2 measures PSNR after compositing over each skin's own page colour, not over white.
4. **A user acts in the first second after launch, before the side files have loaded.** An automatic catalogue refresh must not refetch and overwrite a newer cached list. Task 3 makes every consumer await `ensureSideFiles()` first (test `testRefreshWaitsForSideFiles`).
5. **The 富果 key is added while the app is open.** Live prices must start without a relaunch. Task 4 test `testKeyAddedStartsTheLoop` drives `restart()`.

---

### Task 1: Font subsetting to the app's own characters

**Files:**
- Modify: `Scripts/subset_fonts.py`
- Create: `Scripts/common-chars.txt` (the insurance list in frequency order, with its source and licence in a header comment)
- Modify (regenerated): `App/Resources/Fonts/*.ttf`, `App/Resources/Fonts/*.otf`
- Create test: `Tests/FontCoverageTests.swift`

**Interfaces:**
- `subset_fonts.py` keeps its command line (`python Scripts/subset_fonts.py`, `--check`, `--source <dir>`).
- `charset()` becomes these, in this order:
  - `RANGES` plus the Big5 symbol rows;
  - `app_characters()`, unchanged;
  - every CJK character of `PocketCore/Sources/PocketCore/Resources/catalog.json` and `WebPreview/etf-data.json`, in NFC;
  - the first `INSURANCE` characters of `common-chars.txt`.
- These are removed: `common_traditional()` (Big5 level 1), `SUPPLEMENT`, and `WebPreview/stock-data.json`.
- `INSURANCE` is a module constant. Set it to the largest multiple of 50 that keeps `--check`'s size gate green with at least 50 KB to spare, and print the value it ends at.
- `ORIGINALS` gains the five Latin fonts: `Anton-Regular.ttf`, `BreeSerif-Regular.ttf`, `Caveat-Variable.ttf`, `JetBrainsMono-Regular.ttf` and `PressStart2P-Regular.ttf`.
  - Record each one's source, version (name ID 5), sha256 and a per-font `commit`: the commit where the full file was added (find it with `git log --diff-filter=A -- App/Resources/Fonts/<name>`).
  - `original()` reads `git show <commit>:App/Resources/Fonts/<name>`; the CJK fonts keep `a5573d2`.
  - `SUBSET` becomes every key of `ORIGINALS`.
- `--check` gains two gates:
  - every printable ASCII character is present in each Latin font that had it in its original;
  - `sum(size of App/Resources/Fonts/*.ttf|*.otf) <= 4_000_000` bytes, which fails with `FAIL fonts total N bytes > 4000000`.
- `common-chars.txt` must come from a freely usable list (design §11). Record its URL and licence in the file's header comment. One character per line, most frequent first, Traditional forms.
- `FontCoverageTests` (XCTest, in the app):
  - `testCatalogNamesAreCovered`: for every skin's `title` and `body` font except `DotGothic16-Regular`, every CJK character of every bundled catalogue fund name (`CatalogSnapshot.bundled()`, NFC) is in `CTFontCopyCharacterSet(CTFontCreateWithName(name, 17, nil))`.
  - `testSkinNamesAreCovered`: the same for every `Skin.name` and `Skin.code`.

- [ ] **Step 1: Write `FontCoverageTests`** (assertion messages name the font and the missing characters).

- [ ] **Step 2: Change `subset_fonts.py` per Interfaces, add `common-chars.txt`, and run it locally**

Run: `python Scripts/subset_fonts.py`, then `python Scripts/subset_fonts.py --check`.
Expected: the first prints a total of at most 3.95 MB and the chosen `INSURANCE`. The second prints `ok` for every font, and the size gate passes.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add Scripts/subset_fonts.py Scripts/common-chars.txt App/Resources/Fonts/*.ttf App/Resources/Fonts/*.otf Tests/FontCoverageTests.swift
git commit -m "perf(fonts): subset every font to the app's own text and ETF names, under 4 MB"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected:
- `core` green: `--check` runs there, including the size gate.
- `simulator` green: `FontCoverageTests` and `SkinArtTests.testFontsAreRegistered` pass.
- `skin-matrix` green.
- Spot-check the `ETFToGo-skin-matrix` contact sheet for missing glyphs in all four skins, especially sketch's big numerals.

---

### Task 2: Theme PNGs quantized on export

**Files:**
- Modify: `Scripts/export_skin_art.py`
- Modify (regenerated): `App/Assets.xcassets/Skins/blackgold/**/*.png`, `App/Assets.xcassets/Skins/voxel/**/*.png`
- Create test: `Tests/SkinArtSizeTests.swift`

**Interfaces:**
- `export_skin_art.py` copies every PNG source through `optimize_png(src: Path, dst: Path, page: tuple[int, int, int]) -> tuple[int, float]`, which returns the bytes written and the PSNR.
  - It first writes losslessly (`optimize=True`).
  - If that file is larger than `budget(src)`, it writes `Image.quantize(256, method=Image.Quantize.LIBIMAGEQUANT if available else Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)` instead, saved with `optimize=True`.
  - `budget(src)` is a flat 150 KB per image, which puts the two skins' 24 images under 4 MB.
  - PSNR is measured over the RGB result of alpha-compositing the original and the output on `page`, the skin's own `colors.page` from `skins.json`. That is `#1A1A1D` for black-gold and `#1B1F4B` for voxel.
  - The source files under `design/3d/` are never modified; only the exported copies are.
- `main()` fails, with return code 1 and a printed line per image, when any PSNR is below `PSNR_FLOOR = 36.0` dB or when the black-gold plus voxel PNG total exceeds 4,000,000 bytes. It prints the total and the worst PSNR.
- `SkinArtSizeTests.testQuantizedImagesKeepTheirSize`: every black-gold and voxel `SkinArtName` image still loads (`UIImage(named:)`), and its `size` is unchanged: 1080×1080 for black-gold's `hero_dollar`, `pocket` and `pocket_icon`; 900×900 for voxel's `hero_dollar`; 720×720 for the rest. The byte-size gate lives in the export script, because a compiled `Assets.car` does not expose per-image bytes.

- [ ] **Step 1: Write `SkinArtSizeTests`.**

- [ ] **Step 2: Change `export_skin_art.py` and run it locally**

Run: `python Scripts/export_skin_art.py`
Expected: `exported N images…`, where N is the count the unchanged script printed on a clean tree (run it once before the change to read N), a printed total at most 4,000,000 bytes for black-gold plus voxel, and worst PSNR at least 36.0 dB. `git status` shows only PNG changes under `App/Assets.xcassets/Skins/blackgold` and `voxel`. If any SVG or `Contents.json` changed, stop and find out why.

- [ ] **Step 3: Commit, push, run CI, compare screenshots**

```bash
git add Scripts/export_skin_art.py App/Assets.xcassets/Skins/blackgold App/Assets.xcassets/Skins/voxel Tests/SkinArtSizeTests.swift
git commit -m "perf(art): quantize the 3D theme images on export, checked by PSNR"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. Download `ETFToGo-skin-matrix` from this run and from the last green run before Task 2. Compare `blackgold-lobby.png`, `voxel-lobby.png`, `blackgold-tools.png` and `voxel-skins.png` side by side at 100%: no visible banding or edge halo. If any shows it, raise `PSNR_FLOOR` or the per-image budget for that image and repeat.

---

### Task 3: Side files after the first screen

**Files:**
- Modify: `App/Models.swift`.
  - `init` stops reading `.catalog`, `.official` and `.daily`.
  - Add `ensureSideFiles()`.
  - `refreshCatalog`, `refreshOfficial` and `refresh(symbols:inline:quiet:)` await it first.
- Modify: `App/OpenData.swift`. `refreshDaily` and `followMarket` await it first.
- Modify: `App/ETFToGoApp.swift`. `RootView`'s first `.task` awaits `store.ensureSideFiles()` before `refreshCatalog(automatic:)`.
- Modify tests that read cached side files right after `PortfolioStore(url:)`. Find them with `grep -rn "appendingPathExtension(\"catalog\"\|\"official\"\|\"daily\")" Tests`. Add `await store.ensureSideFiles()` before their asserts.
- Create test: `Tests/LaunchPerformanceTests.swift`

**Interfaces:**
- Produces: `@MainActor func ensureSideFiles() async` on `PortfolioStore`.
  - The first call starts one `Task.detached` that reads and validates the three files with exactly the rules `init` uses today, then assigns `catalog`, `official`, `daily` and `indices` on the main actor.
  - Every call, including concurrent ones, awaits that same task.
  - It is idempotent, and a missing or invalid file is skipped as today. `private(set) var sideFileReads = 0` counts read passes, for tests.
  - Values a refresh has already published win over older cached ones. Each assignment keeps today's newer-than checks (`isNewer(than:)` for official; for catalog, the cached one replaces only the bundled snapshot).

- [ ] **Step 1: Write `LaunchPerformanceTests`**

```swift
func testSideFilesWaitForFirstScreen() async throws {
    // write a valid cached .catalog (fetchedDay today, one extra fund) beside a temp records url
    // store = PortfolioStore(url:) → store.catalog == CatalogSnapshot.bundled()
    // await store.ensureSideFiles() → store.catalog has the extra fund
}
func testEnsureSideFilesIsIdempotent() async  // async let ×2 then a third call → store.sideFileReads == 1, same catalog
func testRefreshWaitsForSideFiles() async {
    // cached .catalog with fetchedDay == DataChecks.day() and one extra fund; fresh store, no ensureSideFiles call
    // await store.refreshCatalog(automatic: true) → store.catalog has the extra fund and store.catalogMessage == nil
    // (any fetch, successful or not, sets catalogMessage, so nil proves it read the cache and skipped the network)
}
func testMigrateTwiceWritesOnce() throws {
    // store with one holding; updateGame { $0.migrate(store.data) } → file modification date d1
    // updateGame { $0.migrate(store.data) } again → modification date still d1
}
```

- [ ] **Step 2: Implement per Interfaces.**

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/Models.swift App/OpenData.swift App/ETFToGoApp.swift Tests/LaunchPerformanceTests.swift <each test file the grep changed>
git commit -m "perf(launch): read the catalogue, dividend and close caches after the first screen"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. UI tests that rely on the cached closes, such as `testAnnualFeesAndHistoryNavigation`, still pass.

---

### Task 4: No live loop without a key; one lighting environment

**Files:**
- Modify: `App/LiveFeed.swift`
- Modify: `App/Design/PocketHero.swift`
- Create test: `Tests/IdleWorkTests.swift`

**Interfaces:**
- `LiveFeed`:
  - `start()` reads the key as today. With an empty key it sets `active = true`, publishes once (`status.hasKey == false`), and starts **no** `loop` task and no socket.
  - `restart()` (called when a key is saved or removed) starts the loop once a key exists.
  - Add `var isLooping: Bool { loop != nil }` (internal, for tests).
  - Add `init(store: PortfolioStore, readKey: @escaping () -> String = { (try? SecureKey.read()) ?? "" })`, so tests can inject the key without touching the keychain.
- `PocketHero`:
  - `@MainActor static func environment() async -> EnvironmentResource?` builds the studio environment at most once per process and caches the result, including a nil from a failed build.
  - Concurrent callers await the same `Task`.
  - Add `@MainActor static private(set) var environmentBuilds = 0`, incremented per build attempt.
  - The `RealityView` make closure calls `environment()` instead of `studioEnvironment()`.

- [ ] **Step 1: Write `IdleWorkTests`**

```swift
@MainActor func testNoKeyNoLoop() {
    // LiveFeed(store:, readKey: { "" }).start() → isLooping == false; stop() → still false
}
@MainActor func testKeyAddedStartsTheLoop() {
    // var key = ""; feed = LiveFeed(store:, readKey: { key }); feed.start() → !isLooping
    // key = "abc"; feed.restart() → isLooping; feed.stop() → !isLooping
}
@MainActor func testEnvironmentIsBuiltOnce() async {
    // let before = PocketHero.environmentBuilds
    // async let a = PocketHero.environment(); async let b = PocketHero.environment(); _ = await (a, b); _ = await PocketHero.environment()
    // XCTAssertLessThanOrEqual(PocketHero.environmentBuilds - before, 1)
}
```

- [ ] **Step 2: Implement per Interfaces.** `LiveFeed`'s other callers (`ConnectionView`, `RootView`) are unchanged.

- [ ] **Step 3: Commit, push, run CI**

```bash
git add App/LiveFeed.swift App/Design/PocketHero.swift Tests/IdleWorkTests.swift
git commit -m "perf(idle): no live-feed timer without a key; one shared 3D lighting environment"
git push origin <branch> && gh workflow run native-ui.yml --repo sonia6891/InvestToGo --ref <branch>
```
Expected: all three jobs green. The black-gold and voxel lobby shots in `skin-matrix` look as lit as before.
