# P0-2 3D 設計系統 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（使用者選擇直接做）。Steps use checkbox (`- [ ]`) syntax.

**Goal:** 做出 3D 示意頁那套「不無聊系列」風格的原生元件：方塊拼成的 3D 數字、立體口袋、金幣、三套皮膚、金幣入袋爆開、音效與觸覺，並以一個「3D 元件展示」頁讓使用者在 TestFlight 實機上看到。

**Architecture:** 幾何與資料（數字由哪些方塊組成、口袋輪廓與縫線位置、皮膚配色與材質參數）放 `PocketCore`，在 Linux 測試；畫面放 `App/Design/`：RealityKit `RealityView` 依核心幾何產生網格，SwiftUI 疊上爆開碎片、六角按鈕與狀態欄列表。

**Tech Stack:** SwiftUI、RealityKit（iOS 18：`RealityView`、`MeshResource.generateBox(size:cornerRadius:)`、`generateCylinder`、`MeshResource(extruding:)`、`PhysicallyBasedMaterial`、`EnvironmentResource(equirectangular:)`）、Core Haptics、AVAudioEngine。

**Spec:** `docs/superpowers/specs/2026-11-11-etf-pocket-redesign-design.md` 第 5.2 節；視覺基準為 3D 示意頁 https://claude.ai/artifact/487rNawBA8gay5GjdFKdzA

## Global Constraints

- 尺寸常數與示意頁相同：數字格寬 `W=1.1`、高 `H=2.0`、筆畫 `T=0.4`、深 `D=0.62`、圓角 `R=0.16`、字距 `GAP=0.32`；七段字形與「每個數字交替 `acg`／`bdf` 為金色」的規則相同。
- 皮膚三套：黑金（傳奇）、橘焰（稀有）、冰藍（普通），色碼與示意頁相同；前景與背景對比 ≥ 4.5。
- 系統「減少動態效果」開啟時：不轉動、不爆開，數字直接換值；音效可在設定關閉；觸覺依系統設定。
- 3D 主角對 VoiceOver 提供數值文字（例如「連續領息 13 個月」）。
- 紅漲綠跌經 `Palette.trend`；畫面文字繁體中文。
- 每個 task：`swift test --package-path PocketCore` 全過；App 端改動由 native-ui CI 編譯與 UI 測試截圖驗證。

## Review Focus

1. 含 `.`、`%`、`−` 與多位數的數字（如 `−0.02%`、`1,240` 去逗號後）排版寬度正確、置中。→ Task 1 `testGlyphLayoutWidthsAndCentering`
2. 未知字元（字母、空白）不當掉，直接略過。→ Task 1 `testUnknownCharactersAreSkipped`
3. 皮膚對比不足會讓文字看不清。→ Task 2 `testSkinTextContrast`
4. 減少動態效果開啟時沒有任何持續動畫。→ Task 4 以 `reduceMotion` 分支，UI 測試啟動參數 `--reduce-motion` 截圖
5. 連點「記錄配息」不會疊加多個動畫或卡住。→ Task 4 `isAnimating` 防重入，UI 測試連點兩次後畫面仍可操作

---

### Task 1: 方塊數字幾何（PocketCore）
**Files:** Create `PocketCore/Sources/PocketCore/Design/BlockGlyphs.swift`；Test `PocketCore/Tests/PocketCoreTests/BlockGlyphsTests.swift`
**Produces:** `struct GlyphBlock: Equatable { enum Shape { case box, ring, slash }; var shape: Shape; var x, y, width, height, depth: Double; var rotation: Double; var gold: Bool }`；`enum BlockGlyphs { static func layout(_ text: String) -> (blocks: [GlyphBlock], width: Double) }`（以 x 置中，原點在字串中心）。
- [ ] 測試：`"12"` → 7 個方塊、寬 `2*W+GAP`；`"0.42%"` 含 1 個點、2 個環、1 個斜槓；`"−0.02%"` 以橫槓開頭；`testUnknownCharactersAreSkipped`（`"A1 2"` 與 `"12"` 相同）；`testGlyphLayoutWidthsAndCentering`（最左與最右方塊邊界對稱於 0）。確認失敗 → 實作 → 通過 → commit。

### Task 2: 口袋幾何與皮膚（PocketCore）
**Files:** Create `Design/PocketShape.swift`、`Design/Skins.swift`；Test `PocketShapeTests.swift`、`SkinsTests.swift`
**Produces:** `enum PocketShape { static func front() -> [SIMD2<Double>]; static func back() -> [SIMD2<Double>]; static func stitches() -> [(center: SIMD2<Double>, angle: Double, length: Double)] }`（取樣自示意頁的二次曲線）；`struct Skin: Identifiable, Equatable { id, name, rarity, background, foreground, muted, accent, line (hex UInt32), matte, matte2, metal: (color, metalness, roughness), burst: [UInt32] }`、`enum Skins { static let all: [Skin]; static let `default`: Skin }`、`func contrastRatio(_:_:) -> Double`。
- [ ] 測試：輪廓封閉且左右對稱、縫線數量與間距固定；三套皮膚 id 唯一、`testSkinTextContrast`（foreground/background ≥ 4.5）。失敗 → 實作 → 通過 → commit。

### Task 3: 皮膚選擇、音效、觸覺、爆開（App）
**Files:** Create `App/Design/SkinStore.swift`（`@Observable`，選擇存 `UserDefaults` 鍵 `pocket.skin`）、`App/Design/Feedback.swift`（`SoundFX.coin()`、`SoundFX.tick()`：AVAudioEngine 合成三角波，與示意頁同頻率；`Haptics.coinDrop()`、`Haptics.tick()`：Core Haptics，不支援時退回 `UIImpactFeedbackGenerator`；設定 `pocket.sound` 預設開）、`App/Design/BurstView.swift`（`TimelineView` + `Canvas` 放射碎片，0.65 秒，顏色取皮膚）、`App/Design/GameControls.swift`（`HexButton`、`HUDRow`、`SkinPicker`）
- [ ] 編譯由 CI；本 task 無核心邏輯，`swiftc -parse` 通過即 commit。

### Task 4: 3D 主角場景（App）
**Files:** Create `App/Design/PocketHero.swift`
**Produces:** `struct PocketHero: View { init(value: String, showsPocket: Bool, skin: Skin, onRecord: Binding<Int>) }` — `RealityView` 依 `BlockGlyphs.layout` 生成 `generateBox(size:cornerRadius:)`／`generateCylinder`／extruded ring；口袋以 `MeshResource(extruding: Path)`；金幣為圓柱＋環；材質 `PhysicallyBasedMaterial`；以程式產生的漸層圖建立 `EnvironmentResource(equirectangular:)` 作反光；一盞方向光加陰影。拖曳轉動、閒置微晃、金幣自轉；`onRecord` 增加時播放金幣下落→爆開→數字彈跳＋音效＋觸覺；`isAnimating` 防重入；減少動態效果時跳過動畫。
- [ ] `swiftc -parse` 通過 → commit。

### Task 5: 「3D 元件展示」頁與 UI 測試
**Files:** Create `App/Design/DesignShowcase.swift`（首頁主角＋「記錄配息」＋皮膚切換＋費用率細項狀態欄列表，資料為示範值並標示）；Modify `App/HomeScreens.swift`（`AppRoute.designShowcase`）、`App/ToolsView.swift`（工具中心加入「3D 元件展示」入口 `tool-design`）、`UITests/ETFToGoUITests.swift`（`testDesignShowcase`：開啟、截圖三套皮膚、連點記錄兩次、`--reduce-motion` 再截圖）
- [ ] CI 全過，截圖送使用者確認手感 → commit。
