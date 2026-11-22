# Android A1：共用測試向量與 `:core` 移植 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `SharedFixtures/vectors/`（輸入＋由 Swift 記錄的預期輸出），並把 PocketCore 全部移植成純 Kotlin 模組 `android/core`，讓兩邊對同一批向量都通過。

**Architecture:** 向量檔是 JSON，一個檔案一個 `kind`（被測的 Swift 函式）。Swift 端在 PocketCore 測試裡新增讀檔測試與「記錄模式」；記錄在 GitHub Actions 的 ubuntu 執行器上跑（這台電腦沒有 Swift）。Kotlin 端 `:core` 是不依賴 Android 的 JVM 模組，型別與函式名稱一對一照抄 Swift，測試讀同一個資料夾。

**Tech Stack:** Kotlin（JVM 17 toolchain）、Gradle Kotlin DSL＋版本目錄、kotlinx.serialization-json、JUnit 5＋kotlin.test；Swift 6 / XCTest（Linux）。

**Spec:** `docs/superpowers/specs/2026-11-22-android-app-design.md`（第 5.1～5.4、7.1～7.4、8.2、10 節）

## Global Constraints

- 工作資料夾 `D:\Projects\ETFToGo-android`，分支 `claude/android`。不得在 `D:\Projects\ETFToGo` 動任何檔案、不得切換那邊的分支。
- 不用 `git add -A`；每次只加本任務列出的檔案。不碰 `marketing/`。
- 不推到 main；可以推 `claude/android` 到 origin（記錄向量需要）。
- 每個提交訊息結尾加上 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- `:core` 不得依賴任何 Android 函式庫；可以 `./gradlew :core:test` 在電腦上跑。
- Kotlin 套件名稱 `com.sonia.etftogo.core`（子套件照 Swift 資料夾：`.support`、`.models`、`.sources`、`.game`、`.analytics`、`.importing`、`.design`）。
- 測試不連網；向量輸入只含 ETF 代號、日期、數字與官方回應樣本，不含任何使用者個人資料。
- 不改 PocketCore 的任何 `Sources/` 檔案（App 層規則搬移是 5.3 節的後續工作，不在 A1）。只新增 PocketCore 的測試檔。
- 使用者看到的文字（錯誤訊息、標題）照抄 Swift 原字串，繁體中文。
- 依賴版本：取執行當下的最新穩定版，寫在 `android/gradle/libs.versions.toml`；Gradle 用 wrapper 並提交 `gradle-wrapper.jar`。

### 移植規則（每個 Kotlin 任務都適用）

| Swift | Kotlin |
|---|---|
| `struct X` | `data class X`，屬性 `val`，預設值照 Swift；`mutating func f(...) -> R` 改成 `fun f(...): Pair<X, R>` 或回傳新的 `X`（R 為 Void 時） |
| `enum X { static func f }`（命名空間） | `object X { fun f }` |
| 有 raw value 的 `enum` | `enum class`，`@SerialName` 用 Swift 的 raw value |
| `extension T { func f }` | 同名頂層擴充函式，放在與 Swift 檔同名的 `.kt` 檔 |
| 具名 tuple | 同檔內的小 `data class`，名稱 = 所在函式名首字大寫＋欄位意義，例如 `Finance.xirr` 的 `(date, amount)` → `CashFlow(date, amount)` |
| `Date` | `java.time.Instant`；JSON 用 `SwiftDateSerializer`（2001-01-01T00:00:00Z 起算的秒數，Double） |
| `Data` | `ByteArray` |
| `Set<T>` | `Set<T>`；寫成 JSON 時依自然順序排序（`YearMonth` 依年月） |
| `UUID` | `java.util.UUID`，JSON 為大寫字串（照 Swift `uuidString`） |
| `Calendar` 台北 | `ZoneId.of("Asia/Taipei")`；所有「月份」「日」的判斷都用台北時區 |
| `throws AppDataError("文字")` | `throw AppDataError("文字")`（`class AppDataError(val text: String): Exception(text)`） |
| `UserDefaults` | 介面 `KeyValueStore`（`fun getBytes(key): ByteArray?`、`fun putBytes(key, value)`、`fun getBool(key): Boolean?`），測試用記憶體實作 |
| `CGRect` | `data class Box(val x: Double, val y: Double, val width: Double, val height: Double)` |
| `SIMD2<Double>` | `data class Vec2(val x: Double, val y: Double)` |
| `Bundle` 內建 JSON | `CoreResources.read(name: String): ByteArray`，從 classpath 讀；Gradle 把 `PocketCore/Sources/PocketCore/Resources/` 設成 `:core` 的 resources 資料夾（不複製檔案） |

JSON 設定：`Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true; coerceInputValues = true }`，定義一次在 `CoreJson.json`。Swift 端寫成 `nil` 的選填欄位（例如 `Portfolio.trades`）在 Kotlin 是 nullable 且預設 `null`，讀寫後不得變成空陣列。

## Review Focus

1. **iPhone 新版備份含 Android 不認得的欄位**：匯入不能失敗，已知欄位全部保留 → Task 4 加 `backupWithUnknownKeyStillDecodes`。
2. **手機時區不是台北**（人在國外）：月份與連續月數仍以台北時間計 → Task 4 加 `yearMonthUsesTaipeiNotDeviceZone`（JVM 預設時區設為 `America/Los_Angeles` 時，`2026-10-31T16:30:00Z` 是 2026-11）。
3. **Big5 CSV 裡有罕用字、或沒有 BOM 的 UTF-16**：結果與 Swift 相同（同樣成功或同樣列出原因）→ Task 8 的向量各一個 case。
4. **數字是 NaN、負數、0 股**：驗證結果與 Swift 相同，不當機 → Task 4、Task 8 的向量各含一個不合法輸入的 case，預期輸出是錯誤文字。
5. **跨年與閏年**：12 月→1 月的連續月數、2 月 29 日的持有週年 → Task 6 的向量含 `2026-12`→`2027-01` 與 `2028-02-29` 的 case。

---

## File Structure

```
SharedFixtures/vectors/
  README.md                       向量格式說明
  support/*.json  models/*.json  sources/*.json  game/*.json
  analytics/*.json  importing/*.json  design/*.json  format/*.json
PocketCore/Tests/PocketCoreTests/
  VectorTests.swift               讀檔、比對、記錄模式、涵蓋檢查
  VectorHandlers.swift            kind → Swift 函式 的對照表
.github/workflows/
  record-vectors.yml              手動觸發：ubuntu 上記錄向量並上傳成 artifact
  android.yml                     android/、SharedFixtures/、PocketCore/ 有變動時：Kotlin 測試＋Swift 測試
android/
  settings.gradle.kts  build.gradle.kts  gradle.properties  gradlew  gradlew.bat
  gradle/libs.versions.toml  gradle/wrapper/*
  PARITY.md
  core/build.gradle.kts
  core/src/main/kotlin/com/sonia/etftogo/core/<子套件>/<與 Swift 同名>.kt
  core/src/test/kotlin/com/sonia/etftogo/core/
    Fixtures.kt  VectorHarness.kt  VectorHandlers.kt  JsonCompare.kt
    <與 Swift 測試同名>Tests.kt   Samples.kt
```

---

### Task 1: Gradle 專案骨架與 `Fixtures`

**Files:**
- Create: `android/settings.gradle.kts`、`android/build.gradle.kts`、`android/gradle.properties`、`android/gradle/libs.versions.toml`、`android/gradle/wrapper/gradle-wrapper.properties`、`android/gradle/wrapper/gradle-wrapper.jar`、`android/gradlew`、`android/gradlew.bat`、`android/.gitignore`
- Create: `android/core/build.gradle.kts`
- Create: `android/core/src/main/kotlin/com/sonia/etftogo/core/support/CoreResources.kt`
- Test: `android/core/src/test/kotlin/com/sonia/etftogo/core/Fixtures.kt`、`.../FixturesTests.kt`

**Interfaces:**
- Produces: `object Fixtures { val root: java.io.File; fun bytes(path: String): ByteArray; fun text(path: String): String }`。`root` 從目前工作目錄往上找名為 `SharedFixtures` 的資料夾（照 Swift `Fixtures.root`），找不到就丟例外並寫明路徑。
- Produces: `object CoreResources { fun read(name: String): ByteArray }`，例如 `read("catalog.json")`。

- [ ] **Step 1: 寫測試**

```kotlin
class FixturesTests {
    @Test fun findsSharedFixtures() {
        assertTrue(Fixtures.root.resolve("official/expected-quotes.json").isFile)
    }
    @Test fun readsBundledCatalog() {
        assertTrue(CoreResources.read("catalog.json").decodeToString().contains("\"0050\""))
    }
}
```

- [ ] **Step 2:** `settings.gradle.kts` 只含 `:core`（之後 A2 加 `:app`）。`core/build.gradle.kts`：`kotlin("jvm")`、`kotlin("plugin.serialization")`、`jvmToolchain(17)`、JUnit Platform；`sourceSets.main.resources.srcDir("../../PocketCore/Sources/PocketCore/Resources")`。`.gitignore` 排除 `.gradle/`、`build/`、`local.properties`。
- [ ] **Step 3:** 在 `android/` 執行 `./gradlew :core:test`。預期：2 tests PASS。
- [ ] **Step 4: Commit** `build(android): core module skeleton reading SharedFixtures`

---

### Task 2: 向量格式與兩邊的讀檔器

**Files:**
- Create: `SharedFixtures/vectors/README.md`、`SharedFixtures/vectors/support/selftest.json`
- Create: `PocketCore/Tests/PocketCoreTests/VectorTests.swift`、`PocketCore/Tests/PocketCoreTests/VectorHandlers.swift`
- Create: `android/core/src/test/kotlin/com/sonia/etftogo/core/JsonCompare.kt`、`VectorHarness.kt`、`VectorHandlers.kt`、`VectorTests.kt`
- Create: `.github/workflows/record-vectors.yml`

**Interfaces:**
- 向量檔格式（寫進 README，兩邊照這個讀）：

```json
{
  "kind": "GameRules.level",
  "platforms": ["swift", "kotlin"],
  "cases": [
    { "name": "zero-xp-is-level-1", "input": { "xp": 0 }, "expected": 1 },
    { "name": "bad-input", "input": { "xp": -5 }, "expected": { "error": "…Swift 原文…" } }
  ]
}
```

  - `kind` = 被測 Swift 函式的完整名稱（`型別.成員`）；同一個 kind 只能有一個檔案。
  - `platforms` 省略時等於兩邊都要。只有 `format.*` 例外（見 Task 3）。
  - 會丟錯的情況，`expected` 是 `{"error": "<AppDataError 文字>"}`。
  - 輸入要讀官方樣本時寫 `{"file": "member/official/A_twse_STOCK_DAY_0050_202506.json"}`（相對 `SharedFixtures/`）。
  - 時間一律寫 ISO-8601 字串（例如 `"2026-11-22T09:00:00+08:00"`），由 handler 轉成 Date／Instant。
  - handler 輸出裡的集合一律先排序。
- Swift：`typealias VectorHandler = (Any) throws -> Any`（輸入、輸出都是 `JSONSerialization` 的值）；`let vectorHandlers: [String: VectorHandler]` 在 `VectorHandlers.swift`。
- Kotlin：`typealias VectorHandler = (JsonElement) -> JsonElement`；`val vectorHandlers: Map<String, VectorHandler>` 在 `VectorHandlers.kt`。丟出 `AppDataError` 時，讀檔器把它轉成 `{"error": text}` 再比對。
- 比對規則 `JsonCompare.equal(a, b): Boolean`（兩邊實作相同）：物件比較鍵集合與各值；陣列依序；字串、布林、null 完全相同；數字在 `|a-b| <= max(1e-9, 1e-12 * max(|a|,|b|))` 內算相同。

- [ ] **Step 1: 寫 `selftest.json`**：kind `Vector.echo`，兩個 case，輸入 `{"value": 1.5}` 和 `{"value": [3,1,2]}`，`expected` 留空不寫。
- [ ] **Step 2: Swift `VectorTests.swift`**：
  - `testAllVectors`：讀 `vectors/**/*.json`，略過 `platforms` 不含 `swift` 的檔案，對每個 case 呼叫 handler。
    - 環境變數 `RECORD_VECTORS=1` 時，把輸出寫回 `expected`（JSON 以 `sortedKeys`、`prettyPrinted` 寫出）。
    - 否則用 JsonCompare 比對；失敗訊息寫出 kind 與 case 名稱。
    - 沒有 `expected` 的 case 直接失敗。
  - `testEveryKindHasSwiftHandler`：每個含 `swift` 的 kind 都在 `vectorHandlers` 裡。
  - `testNoOrphanSwiftHandler`：`vectorHandlers` 的每個鍵都有向量檔。
  - `Vector.echo` 原樣回傳輸入的 `value`。
- [ ] **Step 3: Kotlin `VectorTests.kt`**：
  - 同樣三個測試：`allVectors`、`everyKindHasKotlinHandler`、`noOrphanKotlinHandler`。
  - 不做記錄模式。
  - `JsonCompare` 另外加單元測試：`1.0 == 1`；`0.1+0.2` 對 `0.3` 相同；`[1,2]` 對 `[2,1]` 不同；缺鍵不同。
- [ ] **Step 4: `record-vectors.yml`**：
  - `workflow_dispatch`，`runs-on: ubuntu-latest`。
  - 步驟：checkout 目前分支 → `RECORD_VECTORS=1 swift test --package-path PocketCore --filter VectorTests` → `actions/upload-artifact` 上傳 `SharedFixtures/vectors`，名稱 `vectors`。
  - 不推任何提交（`permissions: contents: read`）。
- [ ] **Step 5: 記錄**：
  1. `git push origin claude/android`。
  2. `gh workflow run record-vectors.yml --ref claude/android`。
  3. 等完成後執行 `gh run download <run-id> -n vectors -D SharedFixtures/vectors`。
  4. 用 `git diff` 確認只有 `expected` 被填入。
- [ ] **Step 6:** `./gradlew :core:test`。預期：Kotlin 三個向量測試 PASS。
- [ ] **Step 7: Commit** `test(vectors): shared vector format with Swift recorder and Kotlin reader`

### 之後每個 Kotlin 任務的固定流程

這段寫一次，Task 3～9 每個都照做：
1. **寫向量輸入。** 照該任務的 kind 清單，在 `SharedFixtures/vectors/<area>/` 建立向量檔，只寫輸入，`expected` 留空。每個 kind 至少要涵蓋三種情況：一般、邊界、不合法輸入。不合法輸入只在函式會丟錯時才需要。
2. **加 Swift handler。** 在 `VectorHandlers.swift` 加上對應的 handler，呼叫現有的 Swift 函式。
3. **記錄。** 照 Task 2 Step 5 的方法記錄並提交，訊息 `test(vectors): record <area>`。
4. **移植測試。** 把該任務對應的 Swift 測試檔移植成同名的 Kotlin 測試：每個 `func testX` 改成 `@Test fun testX`，斷言照抄。
5. **移植原始碼。** 把該任務的 Swift 原始檔移植成同名 `.kt` 檔，照「移植規則」。
6. **加 Kotlin handler。** 在 `VectorHandlers.kt` 加上 handler。
7. **跑測試。** `./gradlew :core:test`，預期全部 PASS（包括移植的測試與該領域的全部向量）。
8. **提交。** 訊息 `feat(core): port <area>`。

---

### Task 3: Support（基礎工具）

**Files（Swift → Kotlin，`support/`）:**
- `DataChecks.swift`、`StableID.swift`、`SHA256.swift`（用 `java.security.MessageDigest` 的 SHA-256，介面照舊）
- `TaiwanMarket.swift`、`TrendRole.swift`、`Upcoming.swift`、`Formatters.swift`、`Platform.swift`（Kotlin 不需要，略過）
- 另新增 `SwiftDateSerializer.kt`、`CoreJson.kt`、`KeyValueStore.kt`、`AppDataError.kt`
- Tests：移植 `SupportTests.swift`、`TrendRoleTests.swift`

**Interfaces:**
- Produces: `object DataChecks { fun code(value: String): Boolean; fun day(date: Instant = Instant.now()): String; fun date(text: String): Instant?; fun rocDay(text: String): String? }`（`day` 以台北時區輸出 `yyyy-MM-dd`，與 Swift 的 `formatter` 相同設定）
- Produces: `object StableID { fun make(namespace: String, value: String): UUID }`：位元組與 Swift 完全相同（SHA-256 取前 16 位元組，第 6 位元組設版本 5、第 8 位元組設變體）。
- Produces: `val CoreJson.json: Json`、`object SwiftDateSerializer : KSerializer<Instant>`、`interface KeyValueStore`、`class MemoryKeyValueStore : KeyValueStore`
- Produces: 頂層函式 `money`、`decimal`、`priceText`、`signed`、`percentText`、`shown`、`weekdayText`、`ymdText`、`wanText`、`monthDay`，名稱與參數同 Swift，數字格式固定用 `Locale.forLanguageTag("zh-TW")`。

**向量 kinds：**
- `DataChecks.code`、`DataChecks.rocDay`、`DataChecks.date`、`StableID.make`、`SHA256Digest.hash`（輸出十六進位小寫字串）、`TaiwanMarket.isOpen`、`TrendRole.init`（輸出 `up`／`down`／`flat`）。
- `format.money`、`format.decimal`、`format.priceText`、`format.percentText`、`format.wanText`：`"platforms": ["kotlin"]`。預期值手寫，依 iPhone 在繁體中文台灣設定下的顯示（例如 `money(1234567)` → `"1,234,567"`、`percentText(-1.5)` → `"-1.5%"`、`wanText(12345678)` → `"1234.6萬"`）。理由：Swift 格式化依裝置語系，Linux 記錄器的語系不同，記錄出來的不能代表 iPhone。README 要寫明這個例外。
  - 涵蓋檢查的例外：Swift 的 `testEveryKindHasSwiftHandler` 本來就略過 `platforms` 不含 `swift` 的檔案。Kotlin 的 `everyKindHasKotlinHandler` 照常要求有 handler。

**Review Focus 測試：**

```kotlin
@Test fun yearMonthUsesTaipeiNotDeviceZone() {
    val saved = TimeZone.getDefault()
    try {
        TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
        assertEquals(YearMonth(2026, 11), YearMonth.of(Instant.parse("2026-10-31T16:30:00Z")))
    } finally { TimeZone.setDefault(saved) }
}
```

（`YearMonth` 在 Task 4 定義，這個測試放在 Task 4 的 `GameStateTests.kt`。）

- [ ] 照「固定流程」1～8。

---

### Task 4: Models（模型、備份格式）

**Files（Swift → Kotlin，`models/`、`game/`、`importing/`）:**
- `Models/CoreModels.swift`、`Models/Research.swift`、`Models/Combo.swift`、`Models/GoalPlanner.swift`、`Models/Planning.swift`、`Models/PriceAlert.swift`、`Models/MemberFeature.swift`
- `Game/GameState.swift`：只移植資料型別 `YearMonth`、`GameState`；`Habit`、`XPEvent` 從 `Quests.swift`、`GameRules.swift` 移過來，放進 `game/GameTypes.kt`。理由：`Portfolio` 需要這些型別。
- `Import/LegacyImport.swift`（`LegacyPlan`、`LegacyPrice`、`BackupImport` 與 `OldDividend`）
- Tests：移植 `PortedAppTests.swift`、`GoalPlannerTests.swift`、`PriceAlertTests.swift`、`MemberFeatureTests.swift`、`NameNormalizationTests.swift`、`ComponentHistoryTests.swift`；並移植 `Samples.swift` → `Samples.kt`（之後每個任務的測試都用它）

**Interfaces:**
- Produces: `data class Portfolio`，欄位名稱、預設值、選填性與 Swift 第 157～179 行相同；`companion object { const val historyLimit = 12; fun decodeBackup(data: ByteArray, limit: Int = 5_000_000): Portfolio; fun validate(history: List<ComponentSnapshot>, of: String) }`；`fun Portfolio.encode(): ByteArray`。
- Produces: `data class YearMonth(val year: Int, val month: Int) : Comparable<YearMonth>`，含 `next()`、`previous()`、`key`、`companion fun of(instant: Instant): YearMonth`（台北時區）、`fun fromKey(key: String): YearMonth?`。JSON 形狀與 Swift 預設 Codable 相同：`{"year":2026,"month":11}`。
- Produces: `object BackupImport { fun decode(bytes: ByteArray): Portfolio }`（舊 PWA v3、舊原生 v1、planning v2、schema 1）
- Produces: `object GoalPlanner`、`object ComboMath`、`object PlanMath`、`object AlertEngine`、`object ResearchMath`，函式同 Swift。

**向量 kinds：**
- `Portfolio.backupRoundTrip`
  - 輸入 `{"file": "vectors/models/backups/<名稱>.json"}`。
  - handler 先 `decodeBackup`，再重新編碼成 JSON 物件輸出。
  - 備份樣本放在 `SharedFixtures/vectors/models/backups/`，至少 4 份：
    - `empty.json`：新安裝的空資料。
    - `full.json`：每個選填欄位都有值，包括 `trades`、`game`、`combo`、`alerts`、`componentHistory`、`fees`。
    - `old-no-optionals.json`：舊版，沒有任何選填欄位。
    - `unknown-key.json`：多一個頂層欄位 `"futureField": 1`。
  - 這些樣本用 Swift 產生：Swift handler 有一個 `Vector.makeBackup` 輸出，或者直接由 Samples 組成，二選一由實作者決定。
- `Portfolio.decodeBackup.rejects`：超過大小上限、`schema` 不支援、歷史超過 12 份。預期輸出是錯誤文字。
- `BackupImport.decode`：每種舊格式至少一份。
- `GoalPlanner.monthlyContribution`、`GoalPlanner.scenarios`、`ComboMath.project`（四種情境）、`PlanMath.project`、`AlertEngine.due`、`AlertEngine.isCurrent`、`ResearchMath.exposures`、`ResearchMath.overlap`、`ComponentSnapshot.imported`、`PriceHistory.validate`。

**Review Focus 測試**（`PortedAppTests.kt` 另加，不是從 Swift 移植的）：

```kotlin
@Test fun backupWithUnknownKeyStillDecodes() {
    val p = Portfolio.decodeBackup(Fixtures.bytes("vectors/models/backups/unknown-key.json"))
    assertEquals(1, p.schema)
}
@Test fun absentOptionalsStayAbsentAfterRoundTrip() {
    val bytes = Fixtures.bytes("vectors/models/backups/old-no-optionals.json")
    val again = CoreJson.json.parseToJsonElement(Portfolio.decodeBackup(bytes).encode().decodeToString()).jsonObject
    assertFalse("trades" in again)
    assertFalse("game" in again)
}
```

另外把 Task 3 列出的 `yearMonthUsesTaipeiNotDeviceZone` 放進 `GameStateTests.kt`。

- [ ] 照「固定流程」1～8。

---

### Task 5: Sources（官方資料與投信持股解析）

**Files（`sources/`）:** `CatalogCore.swift`、`AnnualFees.swift`、`OfficialDataCore.swift`、`OpenDataCore.swift`、`OfficialHistory.swift`、`Fugle.swift`、`IssuerHoldings.swift`；`Research.swift` 裡的 `extension Fugle`（`decodeComponents`、`decodeHistory`）放進 `sources/FugleResearch.kt`。
- Tests：移植 `OpenDataTests.swift`、`OfficialHistoryTests.swift`、`IssuerHoldingsTests.swift`

**Interfaces:**
- Produces: `object OpenData`、`object OfficialHistory`、`object IssuerHoldings`、`object IssuerDirectory`、`object CatalogAPI`、`object Fugle`、`data class OfficialDividends`（含 `companion fun bundled()`、`merging`、`frequency`、`trailingAmount`）、`data class CatalogSnapshot`（`companion fun bundled()`）、`data class AnnualFeeCatalog`（`companion val bundled`），函式同 Swift。
- 解析 HTML 的函式（`fubon`、`fhtrustFundID`）照 Swift 用字串與正規表示式，不加 HTML 函式庫。
- URL 產生函式（`twseMonthURL` 等）回傳 `java.net.URI`。

**向量 kinds：**
- 每個解析函式一個 kind，輸入用 `SharedFixtures/member/**` 與 `SharedFixtures/official/**` 既有的原始回應樣本。
- `OpenData.decodeTWSE`、`OpenData.decodeTPEx` 的預期值必須與既有的 `official/expected-quotes.json` 一致（handler 輸出同樣形狀；兩份都保留）。
- URL 函式一個 kind：`OfficialHistory.urls`，輸入代號與月份，輸出全部 URL 字串。這也確保請求只帶代號與日期。
- `OfficialDividends.merging`、`OfficialDividends.frequency(of:)`、`CatalogAPI.strategy`、`IssuerDirectory.issuer`、`IssuerDirectory.isBondFund`。
- `CatalogSnapshot.bundled.summary`：輸出筆數、`listedDate`、前 5 個代號。這是用來確認兩邊讀到同一份內建名單。

- [ ] 照「固定流程」1～8。

---

### Task 6: Game（遊戲規則）

**Files（`game/`）:** `GameRules.swift`、`Quests.swift`、`Achievements.swift`、`Dex.swift`、`GameTriggers.swift`、`LobbyReplay.swift`（`GameState` 的擴充函式各放在對應的檔案）
- Tests：移植 `GameStateTests.swift`、`GameTriggerTests.swift`、`QuestAchievementTests.swift`、`DexTests.swift`、`LobbyReplayTests.swift`

**Interfaces:**
- Produces: `object GameRules { val xp: Map<XPEvent, Int>; fun xpToReach(level: Int): Int; fun level(xp: Int): Int; fun progress(xp: Int): LevelProgress }`
- Produces: `fun GameState.streak(now: Instant): Int`、`fun GameState.recordDCA(on: Instant, now: Instant? = null): Pair<GameState, List<XPEvent>>`、`logBuy`、`visitFund`（回傳 `Pair<GameState, FundVisit>`）、`logDividend`、`reconcile`、`awardOnce`、`complete`、`refreshAchievements`、`migrate`、`backfillDCA`、`award`、`celebrate`；以及 `Quests.forMonth`、`Achievements.shown`、`Dex.stats`、`LobbySnapshot.of`、`LobbyReplay.between`、`LobbyReplay.arrival`。
- `Achievement.progress` 在 Swift 是閉包；Kotlin 是 `val progress: (GameState, Portfolio, Instant) -> Int`。

**向量 kinds：**
- 純函式：`GameRules.xpToReach`、`GameRules.level`、`GameRules.progress`、`GameState.streak`、`Quests.forMonth`、`Achievements.longestDividendRun`、`Achievements.hasAnniversary`、`Achievements.steady`、`Dex.stats`、`DexSeries.of`、`LobbyReplay.between`、`LobbyReplay.arrival`。
- `Achievements.progressAll`：輸入 state、portfolio、now，輸出每個成就的 `id → progress`。
- `GameState.script`：輸入初始 `GameState`（JSON），以及一串動作，例如 `{"do":"logBuy","on":"…","now":"…"}`、`{"do":"visitFund","symbol":"0050","now":"…"}`、`logDividend`、`reconcile`、`complete`、`refreshAchievements`、`migrate`。輸出每一步回傳的事件，加上最後的 state JSON。至少 8 個腳本，涵蓋：
  - 同月重複定投不再給經驗；
  - 每月經驗上限；
  - 中斷後歸 1，並保留最長紀錄；
  - 新手任務；
  - 圖鑑第一次收錄；
  - `2026-12` → `2027-01` 跨年連續；
  - `2028-02-29` 買進後隔年的週年判斷；
  - 舊資料遷移。

- [ ] 照「固定流程」1～8。

---

### Task 7: Analytics（回測、月報、賣出成本、快照差異）

**Files（`analytics/`）:** `Backtest.swift`、`PocketReport.swift`、`SellCosts.swift`（`UserDefaults` 參數改成 `KeyValueStore`，鍵名照 Swift）、`SnapshotDiff.swift`
- Tests：移植 `BacktestTests.swift`、`PocketReportTests.swift`、`SnapshotDiffTests.swift`

**Interfaces:**
- Produces: `object Finance { fun xirr(flows: List<CashFlow>): Double? }`、`object Backtest { fun maxDrawdown(values: List<Double>): Double; fun run(input: BacktestInput, history: Map<String, SymbolHistory>): BacktestResult }`、`object PocketReport`、`sealed`／`enum ReportPeriod`（形狀照 Swift）、`object SellCosts`、`object SnapshotDiff`。
- `BacktestInput.legs` 改成 `List<BacktestLeg>`（`symbol`、`weight`）；`BacktestResult.curve` 改成 `List<CurvePoint>`（`month`、`invested`、`value`）。

**向量 kinds：**
- `Finance.xirr`（含無解回傳 null）、`Backtest.maxDrawdown`。
- `Backtest.run`：至少 6 個情境：
  - 單檔、配息再投入；
  - 單檔、領現金；
  - 三檔加比例；
  - 上市未滿所選年數；
  - 有分割事件；
  - 有可疑分割（`suspect`）。
- `PocketReport.make`（月報、年報、今年到目前；`showDividends` 開或關）、`PocketReport.earliestMonth`、`PocketReport.noticeDue`、`ReportPeriod.title`。
- `SellCosts.fee`、`SellCosts.net`、`SellCosts.taxRate`（含不同日期）、`SellCosts.preset`、`SnapshotDiff.compare`、`SnapshotDiff.latest`、`SnapshotDiff.shortDay`。

- [ ] 照「固定流程」1～8。

---

### Task 8: Import（券商 CSV、截圖配對）

**Files（`importing/`）:** `BrokerImportCore.swift`、`ScreenshotImport.swift`
- Tests：移植 Swift 測試中涵蓋這兩個檔案的測試。實作者用 `grep -l "CSVTable\|ScreenshotImport\|BrokerPreview" PocketCore/Tests` 找出它們，移植到 `BrokerImportTests.kt`、`ScreenshotImportTests.kt`。

**Interfaces:**
- Produces: `data class CSVTable(val headers: List<String>, val rows: List<List<String>>) { companion fun parse(bytes: ByteArray): CSVTable; fun guess(names: List<String>): Int }`、`data class BrokerMapping`（含 `companion fun guessing(table)`）、`data class BrokerPreview`（含 `companion fun make(table, mapping, broker, account, funds)`）、`object ScreenshotImport`（`combine` 與 `lines` 用 `List<TextBox>`，`data class TextBox(val text: String, val box: Box)`）。
- 文字編碼的判斷順序與 Swift 相同。Big5 用 Java 的 `Charset.forName("Big5")`。如果向量顯示 Swift 解得出、Java 解不出（或解出不同字），改用 `"x-windows-950"`，並在檔案裡註明理由。

**向量 kinds：**
- `CSVTable.parse`：輸入 `{"file": "vectors/importing/csv/<名稱>.csv"}`，以位元組讀取。CSV 樣本至少 8 份：
  - UTF-8、帶 BOM 的 UTF-8、帶 BOM 的 UTF-16LE、沒有 BOM 的 UTF-16LE；
  - Big5（含「碁」「峯」等罕用字）；
  - 千分位沒加引號（欄位比標題多）；
  - 行尾空欄；
  - 國泰證券欄名。
- `BrokerMapping.guessing`、`BrokerPreview.make`：輸出 holdings、skipped 原因、skippedCodes。涵蓋：股或張、總成本或單價、NaN 或負數或 0 股、不在名單的代號、合計列。
- `ScreenshotImport.lines`、`ScreenshotImport.parse`、`ScreenshotImport.review`、`ScreenshotImport.basis`、`ScreenshotImport.plausible`、`ScreenshotImport.combine`：輸入是辨識出的文字與框。至少涵蓋：
  - 多張截圖的重疊列；
  - 融資與融券；
  - 只有名稱沒有代號；
  - 每股價格或總金額的判斷；
  - 判斷不了而留空。

- [ ] 照「固定流程」1～8。

---

### Task 9: Design（外觀主題資料、方塊字形、口袋形狀）

**Files（`design/`）:** `Skins.swift`（解碼 `skins.json`，`SkinColors.extra` 等十六進位色碼照 Swift 轉成 `UInt`）、`BlockGlyphs.swift`、`PocketShape.swift`
- Tests：移植 `BlockGlyphsTests.swift`、`PocketDesignTests.swift`

**Interfaces:**
- Produces: `data class Skin`（形狀照 Swift）、`object Skins { val all: List<Skin> }`（從 `CoreResources.read("skins.json")`）、`object BlockGlyphs { fun layout(text: String): GlyphLayout; fun voxelize(blocks: List<GlyphBlock>, cell: Double): List<GlyphBlock> }`（`GlyphLayout(blocks, width)`）、`object PocketShape { fun front(): List<Vec2>; fun back(): List<Vec2>; fun stitches(): List<Stitch> }`。這些是 A5 的 3D 網格要用的。

**向量 kinds：**
- `Skins.all.summary`：每套的 id、名稱、代碼、全部顏色、字體、style、unlock。
- `BlockGlyphs.layout`：至少 `"1"`、`"12"`、`"100"`、`"$"`、`"0123456789"`。
- `BlockGlyphs.voxelize`：`"12"`，cell = stroke / 2。
- `PocketShape.front`、`PocketShape.back`、`PocketShape.stitches`。

- [ ] 照「固定流程」1～8。

---

### Task 10: CI 與功能對照表

**Files:**
- Create: `.github/workflows/android.yml`
- Create: `android/PARITY.md`

**Interfaces:**
- `android.yml`：
  - 觸發：`push` 到非 main 分支、`pull_request`，路徑篩選 `android/**`、`SharedFixtures/**`、`PocketCore/**`、`.github/workflows/android.yml`。
  - `kotlin` 工作（ubuntu）：`actions/setup-java` 17 → `./gradlew :core:test`（在 `android/` 下），失敗時上傳測試報告。
  - `swift` 工作（ubuntu）：`swift test --package-path PocketCore`。這樣每次改向量，兩邊都會跑。
- `PARITY.md`：
  - 一張表，欄位是「iPhone 畫面或功能」「iPhone 識別碼或 route」「Android 狀態」「對應測試」。
  - 列出設計文件第 6.1～6.11 節的每一項，以及 `App/HomeScreens.swift` 中 `AppRoute` 的每一個 case。
  - A1 只把「規則核心」那些列標為「完成（向量）」，其他標「待做」。

- [ ] **Step 1:** 寫 `android.yml`；推分支，用 `gh run watch` 看兩個工作都綠。
- [ ] **Step 2:** 寫 `PARITY.md`，依 `AppRoute` case 數量逐一核對，不漏列。
- [ ] **Step 3: Commit** `ci(android): run Kotlin and Swift vectors on every change; parity table`

---

### Task 11（habit-loop 合併進 main 之後才做）：一鍵記定投的規則

**條件：** `origin/main` 已經包含 `PocketCore/Sources/PocketCore/Game/QuickDCA.swift`。還沒合併就跳過這個任務，在 `PARITY.md` 標「等 iPhone 合併」。

**Files:** `git merge origin/main`（解衝突時只改本分支自己的檔案）；移植 `Game/QuickDCA.swift` → `game/QuickDCA.kt`；移植 `QuickDCATests.swift`。

**向量 kinds：** `QuickDCA` 裡每個公開的純函式各一個 kind（實作者以 `grep -n "func " QuickDCA.swift` 列出）；`Portfolio.backupRoundTrip` 加一份帶 `quickDCA` 欄位的樣本，並加一份「舊備份沒有這個欄位」的樣本。

- [ ] 照「固定流程」1～8；提交 `feat(core): port quick DCA preset`。

---

## 完成的定義

- `./gradlew :core:test` 全部通過：移植的 PocketCore 測試加上全部向量。
- `swift test --package-path PocketCore` 全部通過：原有 236 項加上向量測試。
- 兩邊的「每個 kind 都有 handler」「沒有多餘的 handler」檢查都通過。
- `android.yml` 在 `claude/android` 上兩個工作都綠。
- 只提交在 `claude/android`；沒有開 PR，要開 PR 等使用者同意。
