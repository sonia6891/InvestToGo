# Android 功能對照表

iPhone 有的每一個畫面與功能，在 Android 上的進度。第一版上架的條件是這張表全部「完成」。

- **完成（向量）**：規則已移到 `android/core`，用 `SharedFixtures/vectors` 和 iPhone 對答案，兩邊的 CI（`.github/workflows/android.yml`）每次都跑。
- **待做**：還沒有 Android 畫面或功能。
- **等 iPhone 合併**：iPhone 的功能還在分支上，合併到 main 之後才移植。
- iPhone 之後新增的功能，補一列，標「Android 待跟上」。

## 一、規則核心（A1）

| iPhone 畫面或功能 | iPhone 識別碼或 route | Android 狀態 | 對應測試 |
|---|---|---|---|
| 資料檢查、代號、日期、穩定識別碼、雜湊、台股開盤時間、漲跌顏色 | `Support/*`（DataChecks、StableID、SHA256、TaiwanMarket、TrendRole、Upcoming） | 完成（向量） | `vectors/support`；`support/SupportTests`、`TaiwanMarketTests`、`CoreJsonTests` |
| 數字與日期文字（金額、價格、百分比、萬） | `Support/Formatters.swift` | 完成（向量） | `vectors/format`（依 iPhone 繁體中文設定手寫）；`support/FormattersTests` |
| 資料模型、備份讀寫、舊格式匯入 | `Models/*`、`Import/LegacyImport.swift` | 完成（向量） | `vectors/models`；`models/PortedAppTests`、`ModelMiscTests` |
| 目標反推、組合試算、規劃 | `Models/GoalPlanner.swift`、`Combo.swift`、`Planning.swift` | 完成（向量） | `vectors/models`；`models/GoalPlannerTests` |
| 到價提醒判斷 | `Models/PriceAlert.swift` | 完成（向量） | `vectors/models`；`models/PriceAlertTests` |
| 官方資料、富果、投信持股、年度費用、ETF 名單 | `Sources/*` | 完成（向量） | `vectors/sources`；`sources/*Tests` |
| 等級、經驗、金幣、連續定投、任務、成就、圖鑑、大廳重播 | `Game/*` | 完成（向量） | `vectors/game`；`game/*Tests` |
| 回測、口袋月報／年報、賣出成本、持股變化 | `Analytics/*` | 完成（向量） | `vectors/analytics`；`analytics/*Tests` |
| 券商 CSV 匯入、截圖匯入解析 | `Import/BrokerImportCore.swift`、`ScreenshotImport.swift` | 完成（向量） | `vectors/importing`；`importing/BrokerImportTests`、`ScreenshotImportTests` |
| 外觀主題資料、方塊數字、口袋形狀 | `Design/*`、`Resources/skins.json` | 完成（向量） | `vectors/design`；`design/BlockGlyphsTests`、`PocketDesignTests` |
| 記一筆（本月定投快速記錄） | `Game/QuickDCA.swift` | 等 iPhone 合併 | — |

## 二、設計文件第 6 節的功能

| iPhone 畫面或功能 | iPhone 識別碼或 route | Android 狀態 | 對應測試 |
|---|---|---|---|
| 6.1 開場動畫 | 開場動畫（設計文件 7.10） | 待做 | — |
| 6.1 新手引導 4 頁（習慣、每月金額與 ETF、提醒、開始） | 新手引導 | 待做 | — |
| 6.1 大廳：連續定投月數、四角入口、等級列、本月任務卡與「記一筆」 | 大廳 | 待做 | — |
| 6.1 六角快選、「‹ 大廳」、返回手勢、第一層下滑回大廳 | 導覽 | 待做 | — |
| 6.1 大廳動態與獎勵重播、LEVEL×UP | `LobbyReplay` | 待做（規則已完成） | `vectors/game/lobbyreplay-*` |
| 6.2 搜尋、分類籤、完整分類、分類依據、我的自選 | `feature(.find)`、`watchlist` | 待做 | — |
| 6.2 ETF 詳情：價格、走勢、持股、配息、資訊、風險、費用、官方配息、加入口袋、用這檔試算 | `fundDetail` | 待做 | — |
| 6.2 圖鑑卡、第一次收進的翻卡 | `dexCard` | 待做 | — |
| 6.3 口袋：總市值、配置條、持有列、三個分頁 | `feature(.pocket)` | 待做 | — |
| 6.3 新增與編輯持有、交易紀錄、資產配置、持股透視 | `holdingForm`、`tradeForm`、`trades`、`allocation`、`exposure` | 待做 | — |
| 6.3 資產總覽 | `overview` | 待做 | — |
| 6.4 配息首頁：今年已領、12 個月打勾圈、月曆、即將除息、近期配息 | `feature(.dividends)`、`recentDividends` | 待做 | — |
| 6.4 配息明細、新增編輯、確認入帳、年度統計與 CSV、本月股息 | `dividendDetail`、`dividendForm`、`dividendDone`、`yearDividends`、`monthDividends` | 待做 | — |
| 6.5 定期定額、股息複利、領息目標、三檔比較、費用比較、組合試算 | `plan`、`calculator`、`goal`、`comparison`、`combo` | 待做 | — |
| 6.5 券商匯入（CSV）與截圖匯入 | `broker` | 待做（規則已完成） | `vectors/importing` |
| 6.5 備份匯出與匯入 | `backup` | 待做（規則已完成） | `vectors/models/backup*` |
| 6.5 提醒中心 | `reminders` | 待做 | — |
| 6.5 資料來源狀態、立即更新、富果金鑰 | `sources`、`connection` | 待做 | — |
| 6.6 成就牆、圖鑑系列、定投紀錄 | `feature(.achievements)`、`dcaHistory` | 待做（規則已完成） | `vectors/game` |
| 6.7 外觀主題 5 套與主題選單（輪播、長按試穿、解鎖） | `skins` | 待做（資料已完成） | `vectors/design/skins-*` |
| 6.7 收成主題（除息季限定） | `skins.json` 第 5 套 | 等 iPhone 合併 | — |
| 6.8 重疊成分 | `exposure`（會員部分） | 待做 | — |
| 6.8 主動式 ETF 追蹤 | `activeTracking` | 待做（規則已完成） | `vectors/analytics/snapshotdiff-*` |
| 6.8 多情境試算 | `combo`（樂觀、保守、壓力測試） | 待做 | — |
| 6.8 存錢目標反推 | `goalPlanner` | 待做（規則已完成） | `vectors/models/goalplanner-*` |
| 6.8 口袋月報／年報 | `report` | 待做（規則已完成） | `vectors/analytics/pocketreport-*` |
| 6.8 回測 | `backtest` | 待做（規則已完成） | `vectors/analytics/backtest-*` |
| 6.8 到價提醒 | `priceAlerts`、`priceAlert` | 待做（規則已完成） | `vectors/models/alertengine-*` |
| 6.9 會員頁與 Google Play 付款、恢復購買 | `member` | 待做 | — |
| 6.10 設定、隱私（含 App 上鎖）、關於、通知中心、資料來源、離線細條、讀取失敗與重試 | `settings`、`privacy`、`about`、`notices`、`sources` | 待做 | — |
| 6.11 主畫面小工具（小、中） | 小工具 | 待做 | — |

## 三、iPhone `AppRoute` 逐項核對（`App/HomeScreens.swift`，45 個）

| iPhone 畫面或功能 | iPhone 識別碼或 route | Android 狀態 | 對應測試 |
|---|---|---|---|
| 物件入口畫面（找 ETF、配息、口袋、工具、成就） | `feature(Feature)` | 待做 | — |
| 定投紀錄（全部月份） | `dcaHistory` | 待做 | — |
| 資產總覽 | `overview` | 待做 | — |
| 本月股息 | `monthDividends(next:)` | 待做 | — |
| 通知中心 | `notices` | 待做 | — |
| 設定 | `settings` | 待做 | — |
| 資料來源 | `sources` | 待做 | — |
| 隱私與 App 上鎖 | `privacy` | 待做 | — |
| 關於 | `about` | 待做 | — |
| 近期配息 | `recentDividends` | 待做 | — |
| 年度配息統計 | `yearDividends` | 待做 | — |
| 配息明細 | `dividendDetail(UUID)` | 待做 | — |
| 新增與編輯配息 | `dividendForm(id:symbol:officialEx:holding:)` | 待做 | — |
| 確認入帳 | `dividendDone(UUID)` | 待做 | — |
| 持有明細 | `holdingDetail(UUID)` | 待做 | — |
| 新增與編輯持有 | `holdingForm(id:symbol:)` | 待做 | — |
| 記一筆交易 | `tradeForm` | 待做 | — |
| 我的自選 | `watchlist` | 待做 | — |
| 分類依據 | `basis(String)` | 待做 | — |
| 圖鑑卡 | `dexCard(String)` | 待做 | — |
| ETF 詳情 | `fundDetail(String)` | 待做 | — |
| 定期定額試算 | `plan` | 待做 | — |
| 領息目標 | `goal` | 待做 | — |
| 股息複利 | `calculator` | 待做 | — |
| 三檔比較 | `comparison` | 待做 | — |
| 持股透視 | `exposure` | 待做 | — |
| 備份 | `backup` | 待做 | — |
| 券商匯入 | `broker` | 待做 | — |
| 富果金鑰（進階連線） | `connection` | 待做 | — |
| 提醒中心 | `reminders` | 待做 | — |
| 口袋會員 | `member` | 待做 | — |
| 外觀主題 | `skins` | 待做 | — |
| 存錢目標反推 | `goalPlanner` | 待做 | — |
| 回測 | `backtest` | 待做 | — |
| 主動式 ETF 追蹤 | `activeTracking` | 待做 | — |
| 口袋月報／年報 | `report` | 待做 | — |
| 到價提醒清單 | `priceAlerts` | 待做 | — |
| 到價提醒（帶入代號） | `priceAlert(String)` | 待做 | — |
| 外觀元件預覽（只在除錯版） | `skinKitPreview` | 待做（除錯用） | — |
| 組合試算 | `combo` | 待做 | — |
| 組合試算：加入標的 | `comboAdding(String)` | 待做 | — |
| 組合試算：設定 | `comboSettings` | 待做 | — |
| 組合試算：結果 | `comboResult` | 待做 | — |
| 交易紀錄 | `trades` | 待做 | — |
| 資產配置 | `allocation` | 待做 | — |
