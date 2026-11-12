# ETF 袋著走 遊戲感介面（iOS）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 iPhone App 從「底部五分頁＋三套配色」改成規格裡的遊戲感介面：大廳＋六角快選、四套完整皮膚（黑金、像素、縫線、手繪）、等級／金幣／任務／圖鑑／成就。

**Architecture:** 皮膚與遊戲規則都是資料與純函式，放 `PocketCore`，在 Linux 用 `swift test` 測；皮膚資料是一份 JSON（安卓之後共用同一份）。App 端只做畫面：畫面向「目前皮膚」要顏色、字體、元件樣式、圖片，不判斷是哪一套。3D 主角沿用既有 RealityKit `PocketHero`（程式產生方塊數字）；縫線與手繪用 SVG 圖。

**Tech Stack:** SwiftUI（iOS 18）、RealityKit `RealityView`、Asset Catalog（PNG @2x/@3x、SVG 保留向量）、隨 App 打包的 OFL 字體、XCTest／XCUITest、GitHub Actions `native-ui.yml`（macOS 26、Xcode 26.6）。

**Spec:** `docs/superpowers/specs/2026-11-12-etf-togo-game-ui-design.md`（帳號、訂閱、資料來源仍依 `docs/superpowers/specs/2026-11-11-etf-pocket-redesign-design.md`）。設計畫布：https://claude.ai/artifact/EYVw8j2Ge95kvCHAKdpqbX

**範圍：** 這份只做 iOS。安卓（Compose）另寫一份計劃，等這份的 Task 1 皮膚 JSON 與 Task 3–5 規則定案後再寫，直接共用 `skins.json` 與規則的測試案例。

## Global Constraints

- 最低 iOS 18；只做 iPhone、直式。
- 這台電腦沒有 Swift。PocketCore 由 CI 的 Linux job 跑 `swift test --package-path PocketCore`；App 由 CI 的 `native-ui.yml` 編譯、跑 UI 測試、截圖。每個 task 完成的定義＝CI 全綠＋截圖與畫布對得上。
- **沒有使用者同意，不 commit、不 push。** 計畫裡的 commit 步驟是「準備好 commit 內容，問使用者」。
- 皮膚四套、順序固定：`blackgold`（黑金 SKN 001）、`voxel`（像素 SKN 002）、`stitch`（縫線 SKN 003）、`sketch`（手繪 SKN 004）。預設黑金。換膚輪播的顯示順序是：像素、黑金、縫線、手繪。
- 顏色一律用名稱取：`page ink sub dim card line accent up down`；色碼照規格 3.1 與 7.1 表，不在畫面程式寫死色碼。
- 紅漲綠跌；每個漲跌都同時有 ▲▼ 與百分比文字，不只靠顏色。
- 示範數字一律用 12；畫面、截圖、測試資料都不出現 13 當示範值（使用者真實資料除外）。
- 經驗、金幣、成就不和投入金額或交易次數掛鉤；成就沒有「存到 X 萬」這類金額目標。
- 可點區域至少 44×44pt；動態字級下大數字最多放大 1.3 倍，不切字。
- 「減少動態效果」開啟：所有移動改淡入淡出、碎片不出現、3D 不轉。
- 3D 主角對 VoiceOver 讀出它代表的值（例：「連續定投 12 個月」）；裝飾不朗讀。
- 畫面文字繁體中文；範例數字標「示意資料」。
- 字體只用 OFL 授權，隨 App 打包，授權檔放 `App/Resources/Fonts/LICENSES/`。
- 皮膚 12 節 G1–G6 的數值目前是**提案**：程式用常數（`GameRules`），改值只改常數與測試期望值。

## Review Focus

1. **舊使用者的皮膚 id**（`ember`、`ice` 已不存在）：讀到不認得的 id 要回到黑金，不當掉、不顯示空白。→ Task 1 `testUnknownOrRetiredSkinFallsBackToBlackGold`
2. **跨年、跳月的定投連續月數**：12 月記了、1 月記了要算連續；中間漏一個月歸 1、保留最長紀錄；同一個月記兩次只算一次。→ Task 3 `testStreakAcrossYearBoundaryAndGaps`、`testSameMonthCountsOnce`
3. **舊備份檔沒有遊戲欄位**：讀 2026-11-11 以前的 `Portfolio` JSON 不可失敗，遊戲進度從 0 開始。→ Task 3 `testPortfolioWithoutGameDecodes`
4. **大數字超過畫面寬**（例：連續 120 個月、LV.100）：要縮小不切字。→ Task 7 `HeroNumber` 以 `ViewThatFits` 縮放，UI 測試啟動參數 `--demo-streak 120` 截圖
5. **新手（沒有任何資料）** 每頁都不能出現 0 元大數字或空白列表。→ Task 8、9 UI 測試 `--reset` 狀態截圖各頁

---

### Task 1: 皮膚資料改成一份 JSON（PocketCore）

**Files:**
- Create: `PocketCore/Sources/PocketCore/Resources/skins.json`
- Modify: `PocketCore/Sources/PocketCore/Design/Skins.swift`（整個換掉資料來源；保留 `contrastRatio`）
- Test: `PocketCore/Tests/PocketCoreTests/PocketDesignTests.swift`（`SkinsTests` 改寫）

**Interfaces:**
- Produces:
  - `struct Skin: Identifiable, Equatable, Decodable` 欄位：`id, name, code`（"SKN 001"）、`colors: SkinColors`、`fonts: SkinFonts`、`style: SkinStyle`、`art: SkinArt`、`feedback: SkinFeedback`、`unlock: SkinUnlock`、`metal: Metal?`（3D 皮膚才有）、`burst: [UInt32]`。
  - `struct SkinColors: Equatable, Decodable { page, ink, sub, dim, card, line, accent, up, down: UInt32; extra: [UInt32] }`（JSON 裡寫 `"#1A1A1D"` 字串，解碼成 UInt32）。
  - `struct SkinFonts { big, title, body, mono: String }`（PostScript 名稱）。
  - `enum SkinStyle` 的各欄位：`tag: TagKind { hexOutline, pixelBlock, paperStrip, highlighter }`、`button: ButtonKind { hex, pixelBlock, paperStitch, sketchBox }`、`stage: StageKind { discRing, pixelFrame, paperDisc, none }`、`check: CheckKind { disc, square, stitchDisc, sketchCircle }`、`quick: QuickKind { goldHex, pinkBlock, stitchDisc, sketchDot }`、`chart: ChartKind { smooth, stepped, plain, pencil }`、`decor: DecorKind { rays, pixelStars, seams, doodles }`。
  - `struct SkinArt { kind: ArtKind { render3D, voxel3D, vector }; folder: String }`（Asset Catalog 資料夾名，例 `Skins/stitch`）。
  - `struct SkinFeedback { sound: String; haptic: HapticKind { heavy, triple, tap, faint } }`。
  - `enum SkinUnlock: Equatable { case free, level(Int), member }`（黑金 free、手繪 level(5)、像素 level(10)、縫線 member — 依 G3、G6 提案）。
  - `enum Skins { static let all: [Skin]; static var default: Skin; static func named(_ id: String) -> Skin; static let carouselOrder = ["voxel", "blackgold", "stitch", "sketch"] }` — `named` 不再回傳 Optional，不認得就回黑金。

- [ ] **Step 1: 改寫 `SkinsTests`**
  - `testFourSkinsInOrder`：`Skins.all.map(\.id) == ["blackgold","voxel","stitch","sketch"]`，名稱 `["黑金","像素","縫線","手繪"]`，`Skins.default.id == "blackgold"`。
  - `testColorsMatchSpec`：黑金 `page 0x1A1A1D, ink 0xF4F1E8, accent 0xF2B632, up 0xF25C54, down 0x3BB273`；像素 `page 0x1B1F4B, accent 0xFF3D8B`；縫線 `page 0xE9DCC3, ink 0x3B2A1A, accent 0xC9573F`；手繪 `page 0xFAF8F3, ink 0x1F1F1F, accent 0xF2D16B`。
  - `testSkinTextContrast`：每套 `ink`／`sub` 對 `page` ≥ 4.5；`up`、`down` 對 `page` ≥ 3（不夠的話調 up/down，記下調整值回報規格）。
  - `testUnknownOrRetiredSkinFallsBackToBlackGold`：`named("ember").id == "blackgold"`、`named("ice")`、`named("")` 同。
  - `testUnlockRules`：`blackgold .free`、`sketch .level(5)`、`voxel .level(10)`、`stitch .member`。
  - `testOnlyVectorSkinsHaveNoMetal`：`stitch`、`sketch` 的 `art.kind == .vector` 且 `metal == nil`。
- [ ] **Step 2: 推 CI 前在本機無法跑，改用 `python -m json.tool PocketCore/Sources/PocketCore/Resources/skins.json` 確認 JSON 格式正確**；CI core job 預期 FAIL（`Skin` 欄位不存在）。
- [ ] **Step 3: 寫 `skins.json` 與解碼**：`Skins.all` 用 `Bundle.module` 讀檔、解碼一次後快取；解碼失敗時 `fatalError` 帶檔名（資料是我們自己的，壞了要立刻知道）。音效檔名 `feedback.sound`：黑金 `thud`、像素 `chip`、縫線 `snip`、手繪 `scribble`（Task 12 放同名 `.caf`）。字體名稱照規格 7.1 表：黑金 `Anton-Regular / NotoSansTC-Black / NotoSansTC-Medium / JetBrainsMono-Regular`；像素 `PressStart2P-Regular / DotGothic16-Regular`；縫線 `BreeSerif-Regular / NotoSerifTC-Black`；手繪 `Caveat-Bold / LXGWWenKaiTC-Bold`。
- [ ] **Step 4: CI core job PASS。** App 端還在用舊欄位（`background`、`foreground`、`surface`…）：同一個 task 裡把 `Palette`（`App/Theme.swift:5-38`）、`SkinStore`、`GameTabBar`、`PocketHero` 改讀新欄位（`background→colors.page`、`foreground→colors.ink`、`muted→colors.sub`、`surface→colors.card`、`surface2→colors.line`），讓 App 先照舊編得過。`SkinStore.next()` 刪掉。
- [ ] **Step 5: CI simulator job 編譯過、既有 UI 測試全過。準備 commit 內容問使用者：** `feat(skins): four skins from one shared skins.json`

### Task 2: 字體與每套皮膚的圖（App 資源）

**Files:**
- Create: `App/Resources/Fonts/*.ttf`（Task 1 列的字體）、`App/Resources/Fonts/LICENSES/*.txt`
- Create: `scripts/export_skin_art.py`（把 `design/3d/` 的 PNG 與 `design/3d/skins/{stitch,sketch_doodle,badges}/` 的 SVG 複製進 `App/Assets.xcassets/Skins/<skinID>/<name>.imageset`，寫 `Contents.json`；SVG 設 `preserves-vector-representation: true`）
- Create: `App/Assets.xcassets/Skins/...`（腳本產出，進版控）
- Modify: `project.yml`（`INFOPLIST_KEY_UIAppFonts` 列出字體檔）、`design/3d/skins/sketch_doodle/draw.mjs`、`design/3d/skins/stitch/stitch.mjs`（補數字 0–9：`digit_0`…`digit_9`，各一張 SVG，與現有 `blocks_12` 同畫風）
- Test: `Tests/SkinArtTests.swift`

**Interfaces:**
- Consumes: Task 1 `Skin.art.folder`、`Skin.fonts`。
- Produces: 圖片名稱固定一組，每套皮膚都要有：`hero_dollar, pocket, pocket_icon, find, dividends, tools, achievements, crown, calc, fees, reminder, goal, badge`，以及 `digit_0`…`digit_9`（vector 皮膚）。取圖一律 `Image("\(skin.art.folder)/\(name)")`。`enum SkinArtName: String, CaseIterable` 放 `PocketCore/Sources/PocketCore/Design/Skins.swift`，名稱就是上面這組（不含 digit）。
- 物件對應照規格 8.2（例：縫線 `find` ＝摺疊地圖，手繪 `find` ＝望遠鏡）。黑金與像素的 PNG 從 Blender 匯出 @2x、@3x：`ETF_SKIN=<id> blender -b --factory-startup --python build_blocks.py -- skinall`。

- [ ] **Step 1: 寫 `testEveryNamedImageExistsForEverySkin`**（`Tests/SkinArtTests.swift`）：對 `Skins.all × SkinArtName.allCases`，`UIImage(named: "\(folder)/\(name)") != nil`；vector 皮膚另外檢查 `digit_0…9`。`testFontsAreRegistered`：每套 `fonts` 的四個名字 `UIFont(name:size:) != nil`。
- [ ] **Step 2: CI 預期 FAIL（找不到圖）。**
- [ ] **Step 3: 補 0–9 的 SVG 數字（draw.mjs、stitch.mjs），跑 `node draw.mjs <out>`、`node stitch.mjs <out>` 產出；跑 `python scripts/export_skin_art.py`；放字體與授權檔；改 `project.yml`。** 本機用無頭 Edge 打開 `sheet.html` 截圖，確認 0–9 與畫布同畫風再往下。
- [ ] **Step 4: CI PASS。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(assets): fonts and per-skin art for all four skins`

### Task 3: 遊戲進度、連續月數、等級（PocketCore）

**Files:**
- Create: `PocketCore/Sources/PocketCore/Game/GameState.swift`、`PocketCore/Sources/PocketCore/Game/GameRules.swift`
- Modify: `PocketCore/Sources/PocketCore/Models/CoreModels.swift`（`Portfolio` 加 `var game: GameState? = nil`）
- Test: `PocketCore/Tests/PocketCoreTests/GameStateTests.swift`

**Interfaces:**
- Produces:
  - `struct YearMonth: Codable, Hashable, Comparable { var year: Int; var month: Int; init(_ date: Date, calendar: Calendar); func next() -> YearMonth }`（日曆一律 `Asia/Taipei`）。
  - `struct GameState: Codable, Equatable { var xp = 0; var coins = 0; var dcaMonths: Set<YearMonth> = []; var longestStreak = 0; var collected: [String: Date] = [:]; var unlocked: [String: Date] = [:]; var questsDone: [String: Set<String>] = [:] }`（`questsDone` 的 key 是 `"2026-11"`）。
  - `enum XPEvent { case monthlyDCA, questDone, firstDexCard, dividendLogged, reconciled }`
  - `enum GameRules { static let xpPerLevel = 300; static let xp: [XPEvent: Int] = [.monthlyDCA: 100, .questDone: 40, .firstDexCard: 30, .dividendLogged: 20, .reconciled: 20]; static func level(xp: Int) -> Int; static func progress(xp: Int) -> (into: Int, needed: Int) }` — `level` 從 1 開始、無上限。
  - `extension GameState { func streak(now: Date) -> Int; mutating func recordDCA(on: Date) -> [XPEvent]; mutating func award(_ e: XPEvent) }` — `recordDCA` 同月第二次回傳 `[]`、不加經驗；連續月數「本月或上個月有記錄」才算還在連續（本月還沒扣款不算中斷）；更新 `longestStreak`。
  - 金幣：每得 1 點經驗得 1 金幣（G2 提案：金幣只換外觀，本計畫只累積、不做商店）。

- [ ] **Step 1: 寫測試**
  - `testLevelEvery300XP`：`level(xp: 0) == 1`、`299 → 1`、`300 → 2`、`3000 → 11`；`progress(xp: 420) == (120, 300)`。
  - `testStreakAcrossYearBoundaryAndGaps`：記 2025-11、2025-12、2026-01、now=2026-01-15 → 3；再記 2026-03、now=2026-03-10 → 1，`longestStreak == 3`。
  - `testStreakStillAliveBeforeThisMonthsDebit`：記到 2026-10，now=2026-11-02 → 仍是連續（=記錄的月數），now=2026-12-01 → 0。
  - `testSameMonthCountsOnce`：同月 `recordDCA` 兩次：第一次 `[.monthlyDCA]`、`xp == 100`，第二次 `[]`、`xp` 不變。
  - `testTwelveMonthDemoStreak`：連續 12 個月 → `streak == 12`（示範值）。
  - `testPortfolioWithoutGameDecodes`：在測試裡寫一段沒有 `game` 欄位的 Portfolio JSON（`{"schema":1,"holdings":[],"dividends":[],"favorites":[],"quotes":{}}`）解碼，`game == nil`；App 讀取時以 `portfolio.game ?? GameState()` 開始。
- [ ] **Step 2: CI core FAIL（型別不存在）。**
- [ ] **Step 3: 實作。** `YearMonth` 的 Comparable 比 `(year, month)`；`streak` 從「本月，若本月沒記錄則上個月」往回數連續存在於 `dcaMonths` 的月份。
- [ ] **Step 4: CI core PASS。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(game): game state, DCA streak and levels`

### Task 4: 本月任務與成就（PocketCore）

**Files:**
- Create: `PocketCore/Sources/PocketCore/Game/Quests.swift`、`PocketCore/Sources/PocketCore/Game/Achievements.swift`
- Test: `PocketCore/Tests/PocketCoreTests/QuestAchievementTests.swift`

**Interfaces:**
- Consumes: Task 3 `GameState`、`YearMonth`、`XPEvent`。
- Produces:
  - `enum Habit: String, Codable, CaseIterable { case dca, dividends, savingGoal }`（新手引導第 1 頁選的習慣）。
  - `struct Quest: Identifiable, Equatable { id: String; title: String; trigger: QuestTrigger }`；`enum QuestTrigger { case dcaLogged, dividendsViewed, newETFResearched, reminderSet, reconciled, firstPlanSet, firstDexCard }`。
  - `enum Quests { static let pool: [Quest]; static func forMonth(_ m: YearMonth, habit: Habit, isNewbie: Bool) -> [Quest] }` — 一律回傳 3 項；新手固定「設定第一筆定投」「收集第 1 張圖鑑卡」＋1 項；同一個月、同一個習慣每次結果相同（以年月當種子，不用亂數）。
  - `extension GameState { mutating func complete(_ q: QuestTrigger, now: Date) -> [XPEvent] }` — 本月任務裡有這個觸發且還沒完成才回 `[.questDone]`。
  - `struct Achievement: Identifiable { id, title: String; goal: Int; progress: (GameState, Portfolio) -> Int }`；`enum Achievements { static let all: [Achievement] }` — 照規格 6.5：連續領息、持有週年紀念、定期定額打卡、一年不亂動、對帳達人、省費達人、體檢完成、ETF 圖鑑、除息季限定皮膚、口袋年報、累計領息里程碑。
  - `extension GameState { mutating func refreshAchievements(_ p: Portfolio, now: Date) -> [String] }` 回傳新解鎖的 id，寫入 `unlocked`。

- [ ] **Step 1: 寫測試**
  - `testThreeQuestsEveryMonthDeterministic`：每個 `Habit` 的 `forMonth` 數量 3、同參數兩次相等、不同月份至少有一個月不同。
  - `testNewbieQuests`：`isNewbie: true` 含 `firstPlanSet` 與 `firstDexCard`。
  - `testQuestCompletesOncePerMonth`：同一觸發第二次回 `[]`。
  - `testNoMoneyTargetAchievements`：`Achievements.all` 的標題沒有一個含「萬」或「元」；包含 id `dividendMilestone`（累計領息里程碑）。
  - `testDCAPunchCardUnlocksAt12`：定期定額打卡 `goal == 12`；`dcaMonths` 12 個月 → `refreshAchievements` 回傳含它，第二次呼叫不再回傳。
- [ ] **Step 2: CI core FAIL。**
- [ ] **Step 3: 實作。** 每項成就的 `goal` 寫在 `Achievements.swift` 頂端常數，旁邊一行註解寫來源（規格 6.5／2026-11-11 文件第 8 節）。
- [ ] **Step 4: CI core PASS。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(game): monthly quests and achievement catalog`

### Task 5: ETF 圖鑑與能力條（PocketCore）

**Files:**
- Create: `PocketCore/Sources/PocketCore/Game/Dex.swift`
- Test: `PocketCore/Tests/PocketCoreTests/DexTests.swift`

**Interfaces:**
- Consumes: 既有 `Fund`（`strategy`、`fundType`、`listingDate`）、`FeeRecord`、Task 3 `GameState.collected`。
- Produces:
  - `enum DexSeries: String, CaseIterable { case marketCap = "市值型", highDividend = "高股息", bond = "債券", theme = "主題" }`；`static func of(_ fund: Fund) -> DexSeries`。
  - `struct DexStats: Equatable { fee, size, yield, volatility, history: Int }`（每項 1–10）。
  - `enum Dex { static func stats(for: Fund, among: [Fund], facts: DexFacts) -> DexStats }`；`struct DexFacts { feeRate: [String: Double]; aum: [String: Double]; yield: [String: Double]; volatility: [String: Double]; listed: [String: Date] }` — G5：費用越低格數越多；規模、歷史依全體排名分 10 級；殖利率、波動依同系列排名分 10 級；缺資料的那一項回 0（畫面顯示「—」）。
  - `extension GameState { mutating func collect(_ symbol: String, now: Date) -> [XPEvent] }`（第一次回 `[.firstDexCard]`）；`func seriesProgress(_ s: DexSeries, funds: [Fund]) -> (got: Int, total: Int)`。

- [ ] **Step 1: 寫測試**
  - `testRankIntoTenBands`：10 檔規模 1…10 → 各自 1…10 格；只有 1 檔 → 10 格；同值同格。
  - `testLowerFeeMoreBars`：費用 0.1% 的格數 > 0.5% 的格數。
  - `testMissingFactIsZero`：沒有殖利率 → `yield == 0`。
  - `testCollectOnce`：同一檔 `collect` 兩次，第二次 `[]`。
- [ ] **Step 2: CI core FAIL。** **Step 3: 實作**（排名分級：`band = ceil(rank / count * 10)`，rank 從 1 開始、由小到大，費用反向）。**Step 4: CI core PASS。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(game): ETF dex series and stat bars`

### Task 6: 皮膚元件組（App）

**Files:**
- Create: `App/Design/SkinKit.swift`（環境值與字體）、`App/Design/SkinShapes.swift`（六角、方塊硬陰影、紙片縫線、手繪框的 `Shape`）、`App/Design/SkinComponents.swift`
- Modify: `App/Design/SkinStore.swift`（`skin` 來自 `Skins.named`；`func select(_ id: String)`；`--skin <id>` 啟動參數供 UI 測試）、`App/Design/GameControls.swift`（舊 `HexButton` 改用新元件）
- Test: `Tests/SkinKitTests.swift`

**Interfaces:**
- Consumes: Task 1 `Skin`、`SkinStyle`；Task 2 字體與圖片名稱。
- Produces（畫面只用這些，不碰 `skin.id`）：
  - `extension EnvironmentValues { var skin: Skin }`；根視圖注入 `.environment(\.skin, SkinStore.shared.skin)`。
  - `enum SkinFont { case big(CGFloat), title(CGFloat), body(CGFloat), mono(CGFloat) }`；`extension View { func skinFont(_ f: SkinFont) -> some View }`（用 `Font.custom(_:size:relativeTo:)` 支援動態字級；`big` 以 `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` 限到約 1.3 倍）。
  - `func skinColor(_ name: KeyPath<SkinColors, UInt32>) -> Color`（`@Environment(\.skin)` 取）。
  - 元件：`SkinTag(_ text: String)`、`SkinButton(_ title: String, primary: Bool = true, action:)`、`SkinChip(_ text: String, selected: Bool, action:)`、`SkinSearchField(text: Binding<String>, prompt: String)`、`SkinCheck(done: Bool)`、`SkinStage<Content: View>(size: CGFloat, content:)`、`SkinDecor(page: DecorPage)`（`enum DecorPage { lobby, splash, other }`；手繪只在 lobby 畫）、`SkinImage(_ name: SkinArtName)`、`SkinCard<Content: View>(content:)`。每個元件內部 `switch skin.style.<kind>`。
  - 所有元件的最小可點區 44×44；`SkinDecor` 加 `.accessibilityHidden(true)`。

- [ ] **Step 1: 寫測試** `Tests/SkinKitTests.swift`：`testEveryStyleKindHasARendering` — 對每套皮膚把每個元件用 `ImageRenderer` 畫成圖，`uiImage != nil` 且尺寸 > 0（抓 switch 漏 case 或資源缺）；`testButtonsMeetMinimumHitSize` — `SkinButton`、`SkinChip` 的 `ImageRenderer` 輸出高 ≥ 44。
- [ ] **Step 2: CI FAIL。** **Step 3: 實作**（樣式數值照畫布：六角切角 = 高的 0.28；像素硬陰影偏移 4pt、白框 2pt；縫線虛線 `[6,5]`、內縮 6pt、紙片陰影 `rgba(80,52,24,.22)` 偏移 (2,3)；手繪框用固定種子的抖動路徑，同一元件每次畫出來一樣）。
- [ ] **Step 4: CI PASS；** 加一個 DEBUG 才有的「元件總表」頁（`AppRoute.skinKitPreview`），UI 測試 `testSkinKitSheet` 以 `--skin` 四套各截一張，和畫布「四套皮膚」畫板並排比對。
- [ ] **Step 5: 準備 commit 問使用者：** `feat(design): skin component kit driven by skin data`

### Task 7: 大廳、六角快選、拿掉底部分頁（App）

**Files:**
- Create: `App/Lobby/LobbyView.swift`、`App/Lobby/HeroNumber.swift`、`App/Lobby/QuickPick.swift`、`App/Lobby/GameBottomBar.swift`
- Modify: `App/ETFToGoApp.swift`（`RootView` 改成 `NavigationStack(path:)` 以大廳為根；刪 `TabView`、`resets`、`--tab`，改 `--open <feature>`）、`App/HomeScreens.swift`（`AppRoute` 加 `case feature(Feature)`）、`App/Design/PocketHero.swift`（材質讀 `skin.metal`；`art.kind == .voxel3D` 時方塊以 `BlockGlyphs.voxelize` 排）、`.github/workflows/native-ui.yml`（截圖迴圈改 `--open lobby find dividends pocket tools achievements`）
- Delete: `App/Design/GameTabBar.swift`；`App/Theme.swift` 裡的 `AppTabs`、`tabBarMinimize`
- Modify: `PocketCore/Sources/PocketCore/Design/BlockGlyphs.swift`（加 `static func voxelize(_ blocks: [GlyphBlock], cell: Double) -> [GlyphBlock]`）
- Test: `PocketCore/Tests/PocketCoreTests/BlockGlyphsTests.swift`、`UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 3 `GameState.streak`、`GameRules.level/progress`；Task 4 `Quests.forMonth`；Task 6 元件。
- Produces:
  - `enum Feature: String, CaseIterable, Hashable { case find, dividends, pocket, tools, achievements }`，`title`：找 ETF、配息、口袋、工具、成就；`art: SkinArtName`。
  - `struct GameBottomBar: View { let title: String; var onLobby: () -> Void; var onPick: (Feature) -> Void }` — 左「‹ 大廳」、中快選鈕、右金字頁名。識別碼：`bar-lobby`、`bar-quick`。
  - `struct QuickPick: View { @Binding var open: Bool; var pick: (Feature) -> Void }` — 五個圓盤沿弧線，識別碼 `quick-<feature>`；減少動態效果時直接淡入。
  - `struct HeroNumber: View { let value: Int; let caption: String }` — 3D 皮膚用 `PocketHero(value:)`，vector 皮膚用 `digit_N` 圖並排；`ViewThatFits` 縮小；`accessibilityLabel("連續定投 \(value) 個月")`。
  - `LobbyView`：頂部 LV／經驗條／金幣／靶心（識別碼 `lobby-achievements`）、中央 `HeroNumber`（點了開 `AppRoute.dcaHistory`）、四角入口（識別碼 `lobby-find` `lobby-dividends` `lobby-pocket` `lobby-tools`）、本月任務卡、「→ 點物件進入 ←」。新手（`dcaMonths` 空）：單獨的 1、「第 1 個月」「今天開始」；中斷：顯示「最長紀錄 N 個月」。
  - 手勢：左緣右滑回上一層（`NavigationStack` 內建）；第一層功能頁往下滑（`DragGesture` 位移 > 120pt 且起點在上方 1/3）回大廳。
  - 進入動畫：物件 `matchedGeometryEffect` 放大淡出約 350ms；減少動態效果改淡入淡出。
  - 示範啟動參數（只在 `--ui-testing` 時有效）：`--demo-streak <n>` 把 `dcaMonths` 設成到本月為止連續 n 個月；`--demo-xp <n>` 設經驗；`--demo-level <n>` 設經驗為 `(n-1)*GameRules.xpPerLevel`；`--skin <id>`（Task 6）；`--offline`、`--reduce-motion`（Task 12 讀）。集中在 `App/Lobby/DemoArguments.swift` 的 `enum DemoArguments { static func apply(to: inout GameState, args: [String], now: Date) }`。

- [ ] **Step 1: 寫測試**
  - PocketCore `testVoxelizeKeepsBoundsOnGrid`：`voxelize(layout("12").blocks, cell: 0.25)` 每塊寬高都等於 0.25、所有中心落在格點、外框和原來相差 < 一格。
  - UI `testLobbyEntriesAndBack`：`--ui-testing --reset --demo-streak 12`；大廳看得到 `連續定投 12 個月`；依序點 `lobby-find/dividends/pocket/tools/achievements`，每頁按 `bar-lobby` 回到大廳（以 `lobby-find` 存在判定）。
  - UI `testQuickPickSwitchesEveryFeature`：從找 ETF 開始，`bar-quick` → `quick-<f>` 逐一切換，頁名文字等於該功能標題；再按 `bar-quick` 收起，五個 `quick-*` 消失。
  - UI `testNewbieLobby`：`--reset` 無 demo → 看得到「今天開始」「設定第一筆定投」。
  - UI `testHugeStreakFits`：`--demo-streak 120`，`HeroNumber` 的 frame 寬 ≤ 視窗寬。
  - UI `testNoTabBar`：`app.tabBars.count == 0`。
- [ ] **Step 2: CI FAIL。** **Step 3: 實作**，並把舊 UI 測試裡 `tab-…` 的點擊改成 `--open` 或大廳入口。**Step 4: CI PASS，截圖與畫布「大廳」「六角快選」比對。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(nav): lobby and hex quick-pick replace the tab bar`

### Task 8: 找 ETF、ETF 詳情、圖鑑卡（App）

**Files:**
- Modify: `App/DiscoverViews.swift`、`App/ResearchViews.swift`（詳情）、`App/MarketViews.swift`（走勢線依 `style.chart`）
- Create: `App/Dex/DexCardView.swift`、`App/Dex/DexStore.swift`（把 Task 5 `Dex.stats` 接上既有的費用、規模、配息資料）
- Test: `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 5 `Dex`、`GameState.collect`；Task 6 元件；Task 7 `Feature.find`。
- Produces: `struct DexCardView: View { let symbol: String }`（`AppRoute.dexCard(String)`），左右滑換卡；能力條 10 格方塊、缺資料顯示「—」；「特技」一句白話（來自 `Fund` 的類型與費用，不寫推薦語）；按鈕「PK 比一比」（開既有比較頁）、「加入口袋」。打開詳情時呼叫 `collect`，第一次收集跳一個小提示「收進圖鑑 +30 經驗」。

- [ ] **Step 1: 寫 UI 測試** `testFindDetailAndDex`：`--open find`；分類籤 `高股息` 篩選後每列都有 ▲ 或 ▼；搜尋 `0050` → 點列 → 詳情顯示 `0050` 與分頁籤 走勢／持股／配息／資訊；第一次打開出現「收進圖鑑」；點「圖鑑卡」看到五條能力條（識別碼 `dex-bar-fee` 等）；再打開同一檔不再出現提示。
- [ ] **Step 2: CI FAIL。** **Step 3: 重排三頁版面照規格 5.4–5.6，全部改用 Task 6 元件。** **Step 4: CI PASS，四套皮膚各截一次和畫布比對。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(find): game-style ETF search, detail and dex card`

### Task 9: 口袋、配息（App）

**Files:**
- Modify: `App/PortfolioViews.swift`、`App/DividendScreens.swift`、`App/HomeDashboard.swift`（拆掉舊首頁儀表板中已被大廳取代的部分）
- Test: `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 6 元件、Task 3 `award(.dividendLogged)`、Task 4 `complete(.dividendsViewed)`。
- Produces: 口袋頁照 5.7（3D 口袋、`我的口袋 · N 檔`、總市值大數字、總損益標籤、配置條、持股列、「＋ 加一檔」）；配息頁照 5.8（金幣堆、今年已領、12 個月打勾圈用 `SkinCheck`、即將除息、「記一筆配息」→ 存檔後 `award(.dividendLogged)` 並播投幣動畫）。新手：物件＋一句說明＋一個按鈕，沒有 0 元大數字。虧損照實用 `down` 色顯示，沒有懲罰動畫或負面文案。

- [ ] **Step 1: 寫 UI 測試**
  - `testNewbiePocketAndDividendsHaveNoZeroHero`：`--reset --open pocket`：沒有 `NT$ 0`、看得到「＋ 加一檔」；`--open dividends` 同理，看得到「記一筆配息」。
  - `testLogDividendGivesXP`：記一筆配息 → 回大廳經驗條數值增加 20。
  - 既有 `testHoldingSurvivesRelaunch` 改成從口袋頁操作，照樣通過。
- [ ] **Step 2: CI FAIL。** **Step 3: 實作。** **Step 4: CI PASS，四套皮膚截圖比對畫布。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(pocket): game-style pocket and dividends`

### Task 10: 工具箱、會員、換膚輪播（App）

**Files:**
- Modify: `App/ToolsView.swift`、`App/Design/DesignShowcase.swift`（換膚頁取代舊展示頁）
- Create: `App/Skins/SkinCarousel.swift`、`App/Membership/MemberView.swift`
- Test: `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 1 `Skins.carouselOrder`、`SkinUnlock`；Task 3 `GameRules.level`；Task 2 `badges` 圖（`Skins/badges/<id>`）、各皮膚 `pocket` 圖。
- Produces:
  - 工具箱兩欄卡（5.9），最後一張「會員・換膚」用主色。
  - `MemberView`：三個方案卡、主按鈕、恢復購買、條款、隨時可取消；**價格從 StoreKit 取**（`Product.products(for:)`），拿不到時顯示「—」與「再試一次」，不寫死價格。實際購買流程依 2026-11-11 文件另案，這裡只接到 `Product.purchase()` 的按鈕。
  - `SkinCarousel`：`ScrollView(.horizontal)` + `scrollTargetBehavior(.viewAligned)`，順序 `carouselOrder`；卡片只放該皮膚的 `pocket` 圖＋底色，**沒有數字**；中間卡放大加白框、左右露出鄰居；頁點＋「n / 4」；名稱、狀態標籤（使用中／已解鎖／`LV.N`／會員）、一句說明；四個風格圖示（`badges`）點了跳到那張；按鈕：使用中→「← 滑動試穿 →」、已解鎖→「換上這套」（`SkinStore.select`）、未解鎖→「去升級」或「看會員」；長按卡片＝全螢幕試穿，放開還原（試穿只改預覽，不改 `SkinStore`）。識別碼：`skin-card-<id>`、`skin-badge-<id>`、`skin-apply`。
  - `func isUnlocked(_ s: Skin, level: Int, member: Bool) -> Bool` 放 PocketCore `Skins.swift`。

- [ ] **Step 1: 寫測試**
  - PocketCore `testIsUnlocked`：LV.4 非會員 → 只有黑金；LV.5 → 加手繪；LV.10 → 加像素；會員 → 四套。
  - UI `testSkinCarousel`：`--demo-level 7`；`--open tools` → 會員・換膚 → 換膚；預設停黑金、狀態「使用中」、按鈕「← 滑動試穿 →」；點 `skin-badge-sketch` → 標籤含「已解鎖」、按 `skin-apply` → 回大廳，大廳背景取樣色 = `0xFAF8F3`（用截圖取中心上方空白點像素）；點 `skin-badge-stitch` → 按鈕是「看會員」。
  - UI `testCarouselShowsNoNumbers`：輪播頁的 `staticTexts` 沒有任何純數字標籤（排除「n / 4」與 LV）。
- [ ] **Step 2: CI FAIL。** **Step 3: 實作。** **Step 4: CI PASS，截圖與畫布「遊戲系統」畫板（停在黑金／滑到手繪）比對。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(skins): tools, membership and the skin carousel`

### Task 11: 開機、新手引導、成就、升級（App）

**Files:**
- Create: `App/Onboarding/SplashView.swift`、`App/Onboarding/OnboardingFlow.swift`、`App/Game/AchievementsView.swift`、`App/Game/LevelUpView.swift`、`App/Game/DCAHistoryView.swift`
- Modify: `App/ETFToGoApp.swift`（第一次開啟走 開機 → 引導 4 頁 → 大廳；`@AppStorage("onboarded")`；`--skip-onboarding` 給既有 UI 測試）
- Test: `UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 4 `Habit`、`Achievements.all`、`refreshAchievements`；Task 3 `GameRules`；Task 6 元件。
- Produces:
  - 開機（5.1）：光片＋舞台＋`hero_dollar`、`SKN×001`（取 `skin.code`）、皮膚名標籤、「存 ETF，也存下好習慣。」、「→ 輕點開始 ←」。
  - 引導（5.2）：四段進度條可返回；1 習慣（存 `Habit`）、2 金額 1,000／3,000／5,000／10,000 與 ETF（0050、006208、00878、搜尋其他）、3 扣款日 3–9、提醒時間、前一天也提醒（接既有 `DividendReminders` 的通知權限流程）、4 登入：Apple、Google、Email 連結、條款 — 登入本身依 2026-11-11 文件另案，這裡按鈕先接「稍後再說」進大廳。
  - 成就（5.11）：三欄徽章牆；已解鎖＝舞台＋物件＋日期；未解鎖＝暗色問號＋進度條＋數字。
  - 升級（5.12）：`LEVEL×UP`、`LV.N`、原因標籤、獎勵、「收下」「分享這一刻」（`ShareLink` 分享一張 `ImageRenderer` 畫的圖）。升級在 `GameState` 經驗跨過整級時，由根視圖以 `fullScreenCover` 顯示一次。
  - 定投紀錄（點大廳數字）：所有月份的打勾圈與最長紀錄。

- [ ] **Step 1: 寫 UI 測試**
  - `testFirstLaunchOnboarding`：`--ui-testing --reset`（不帶 `--skip-onboarding`）→ 點開機 → 選「定期定額」→ 下一步 → 選 3,000 與 0050 → 下一步 → 扣款日 6 → 下一步 → 「稍後再說」→ 大廳出現；再啟動（不帶 `--reset`）直接進大廳。
  - `testBackInOnboarding`：第 3 頁按返回回到第 2 頁，選過的 3,000 仍選中。
  - `testAchievementWall`：`--demo-streak 12 --open achievements` → 「定期定額打卡」顯示已解鎖與日期；任一未解鎖顯示進度數字。
  - `testLevelUpShowsOnce`：`--demo-xp 290` → 記一筆配息（+20）→ 出現 `LV.2`，按「收下」；回大廳再進出一次不再出現。
- [ ] **Step 2: CI FAIL。** **Step 3: 實作。** 既有 UI 測試的啟動參數全部加 `--skip-onboarding`。**Step 4: CI PASS，截圖比對畫布「開機」「新手引導」「遊戲系統」。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(game): splash, onboarding, achievements and level-up`

### Task 12: 每套皮膚的音效與震動、狀態與輔助使用（App）

**Files:**
- Modify: `App/Design/Feedback.swift`（依 `skin.feedback`）、`App/Design/BurstView.swift`（減少動態效果時不出現）
- Create: `App/Resources/Sounds/{thud,chip,snip,scribble}.caf`、`App/Design/OfflineBar.swift`、`App/Design/LoadingFloat.swift`
- Test: `Tests/FeedbackTests.swift`、`UITests/ETFToGoUITests.swift`

**Interfaces:**
- Consumes: Task 1 `SkinFeedback`；Task 6 元件。
- Produces:
  - `enum SoundFX { static func confirm(_ skin: Skin, enabled: Bool) }`（讀 `App/Resources/Sounds/<feedback.sound>.caf`）；`enum Haptics { static func confirm(_ kind: HapticKind) }`：heavy＝一下 `.heavy`、triple＝三下 `.rigid` 間隔 60ms、tap＝一下 `.light`、faint＝一下 `.soft` 強度 0.3。
  - 投幣動畫依 `skin.art.kind` 與 id 無關：3D 皮膚＝金幣掉進口袋＋碎片；vector 皮膚＝圖片彈一下＋`+1`。（規格 7.1 的四種投幣演出，第一版只做到這兩種，縫線「縫進口袋」與手繪「正字多一筆」列為之後，見下方「不在這份」。）
  - `LoadFailed(message:retry:lastUpdated:)`：白話說明＋「再試一次」，下方仍顯示上次成功的資料與時間；找 ETF、詳情、配息三頁的讀取失敗都改用它。
  - `OfflineBar`：頂部細條「離線中 · 顯示 MM/DD HH:mm 的資料」；`LoadingFloat`：物件浮動＋等寬字「讀取中」，取代轉圈。
  - 設定頁加「音效」開關（沿用 `pocket.sound`）。

- [ ] **Step 1: 寫測試**
  - `Tests/FeedbackTests.swift` `testEverySkinSoundFileExists`：每套 `Bundle.main.url(forResource: feedback.sound, withExtension: "caf") != nil`。
  - UI `testReduceMotionStillWorks`：`--reduce-motion`（App 讀到時視同系統設定開啟）走一次 大廳 → 配息 → 記一筆 → 回大廳，流程不卡、沒有 `burst` 識別碼出現。
  - UI `testLargestTextMainFlow`：`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` 走大廳 → 找 ETF → 詳情，主要按鈕都 `isHittable`。
  - UI `testSkinSwitchLeavesNoOldColor`：`--skin blackgold` 換到手繪後，依序截大廳、找 ETF、口袋、配息、工具，每張圖背景取樣都等於 `0xFAF8F3`，且不含 `0xF2B632`（掃整張圖，容許 ±6）。
  - UI `testOfflineBar`：`--offline` 顯示「離線中」；`--open find` 時列表仍顯示上次的資料，並有「再試一次」。
- [ ] **Step 2: CI FAIL。** **Step 3: 實作**（音效檔用 AVAudioEngine 既有合成器錄出或自製，不取用第三方素材）。**Step 4: CI PASS。**
- [ ] **Step 5: 準備 commit 問使用者：** `feat(feel): per-skin sound and haptics, states and accessibility`

### Task 13: 全畫面驗收

**Files:**
- Modify: `.github/workflows/native-ui.yml`（截圖改成 4 套皮膚 × 9 個畫面：開機、引導 1、大廳、找 ETF、詳情、圖鑑卡、口袋、配息、工具、換膚、成就；檔名 `<skin>-<screen>.png`；`--demo-streak 12 --demo-level 7`）
- Create: `scripts/contact_sheet.py`（把 CI 截圖拼成和畫布同排列的對照表）

- [ ] **Step 1: 跑 CI，下載截圖，拼對照表，和畫布逐張比對**（啞光感、光的方向、顏色、字體、元件形狀）。列出差異。
- [ ] **Step 2: 修完差異再跑一次，對照表送使用者看。**
- [ ] **Step 3: 效能：** 用 TestFlight 版本在 iPhone 12 等級的機器，Instruments 的 Animation Hitches 看大廳 3D 30 秒，目標 60fps；不到就降 `PocketHero` 的方塊圓角分段數，再測。
- [ ] **Step 4: 準備 commit 問使用者：** `chore(ci): four-skin screenshot matrix`

---

## 不在這份（之後另案）

- 安卓 Compose 版（另一份計劃，共用 `skins.json` 與 Task 3–5 的測試案例）。
- USDZ／GLB 匯出（規格 8.2 的會動主角）：第一版 iPhone 用 RealityKit 程式產生方塊（Task 7），不另外匯出模型；安卓計劃再決定 GLB。
- 縫線「硬幣縫進口袋」、手繪「正字多一筆」兩種專屬投幣演出；金幣商店；除息季限定皮膚；主物件專屬造型。
- 登入、訂閱購買實際流程（依 2026-11-11 文件的階段）。
- 規格 12 節 G1–G6 定案後，只改 `GameRules`、`skins.json` 的 `unlock` 與對應測試期望值。
