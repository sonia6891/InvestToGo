# 投資袋著走 — TestFlight 發佈紀錄

更新日期：2026-10-29（台灣時間）。唯一持續開發來源為本 SwiftUI 工程，開發分支為 `ui/pocket-redesign`。**0.3.0 已於 2026-10-18 上傳 TestFlight 並交給內部測試；尚未確認使用者已在 iPhone 安裝這個版本。**

## 2026-10-18 改版上傳 TestFlight

- [native-ui run 39159534805](https://github.com/sonia6891/InvestToGo/actions/runs/39159534805) 使用來源 `71a8782632a003e159057d52b7768cb0f71befc3`：編譯、單元測試與 UI 測試成功。
- [TestFlight run 39161906093](https://github.com/sonia6891/InvestToGo/actions/runs/39161906093) 使用同一來源：以 App Store Connect API 金鑰簽署封存、上傳成功，並等到這個建置完成處理後交給內部測試群組。
- 使用者是否已更新並開啟這個版本，尚待回報；不把上傳成功當成實機驗證。

## 2026-10-29 分支整併（`claude/optimization-updates-refinement-ccqlsj`，**未編譯、未測試**）

此環境沒有 Swift／Xcode，只做過 tree-sitter 語法剖析（30 個 Swift 檔 0 錯誤）。須重跑 native-ui 才算驗證。

- 移植 `claude/perf-optimizations`（原本基於舊 main）：日期格式器改為共用，不再於每次存檔驗證歷史價格時逐筆重建；網路請求共用同一個不轉址的連線；歷史日期排序檢查改為逐筆比較。報價批次中途失敗時保留已取得報價，改版已有，不重複移植。
- 從 `claude/stocks-and-scenarios`（同樣基於舊 main）只移植改版缺少的部分：持股透視把直接持有的個股併入同一檔股票的曝險，價格與持有市值同樣來源；個股不再出現在「取得成分股」清單。個股持有、情境試算與以總成本輸入，改版已有，其餘不移植。
- 新增單元測試：歷史日期亂序與無效日期、直接持有個股併入曝險。
- 存檔上限：歷史走勢改存於 `portfolio.json.histories`，紀錄檔不再因走勢累積超過 5 MB 而無法儲存；舊版超過上限的紀錄檔仍可開啟，下次儲存時把走勢移出。備份不含走勢（可重新取得）。紀錄本身超過上限時改顯示明確訊息。
- CSV 匯入：行尾空欄與較短的列自動對齊；無效代號、數量或成本、不在名單的代號、欄位過多的列改為略過並在預覽列出原因，不再整份拒絕；替換帳戶時保留略過列上代號的既有庫存。截圖匯入維持逐筆修正。
- 新增測試：走勢與紀錄分開儲存及舊檔移轉、CSV 略過列、替換帳戶保留略過的部位。

## 0.3.0 介面改版（ui/pocket-redesign 分支），已編譯並通過測試，尚未上傳

- 2026-10-16 依新範本加入台股個股與大盤、個股＋ETF 組合試算、新 App 圖示（口袋金幣）。[native-ui run 38843830883](https://github.com/sonia6891/InvestToGo/actions/runs/38843830883) 使用來源 `83731b854b3fb6c4151f0fd91b3e6f74928cbf36`：**編譯成功、32 項單元測試與 5 項 UI 測試全部通過**。新增測試：組合試算公式與範本數字一致（734,181／1,061,022／2,032,300）、壓力測試與股息不再投入、內建個股資料讀取、個股以收盤價估值與試算設定保存；UI 測試走完「探索個股 › 個股詳情（財務、股利）› 加入試算 › 試算設定 › 試算結果」。
- 個股資料由 `WebPreview/build_stocks.py` 從證交所、櫃買中心開放資料產生 `stock-data.json`（網頁版與 App 共用）：公司名單、最近交易日收盤、加權／櫃買指數、月營收、EPS、股利。沒有富果金鑰時顯示收盤價並標資料日；有金鑰時用富果即時報價與 IX0001／IX0043 指數。這份資料目前由人工執行更新，尚未每日自動更新。
- 修正：推入的畫面先前沒有避開懸浮導覽列，ETF／個股詳情底部按鈕被導覽列蓋住；現在每個推入畫面都保留導覽列的空間。
- 2026-10-16 使用者同意把本程式庫改為公開，改用 GitHub 的 `macos-26` 建置機（公開程式庫免費）。[native-ui run 38792912016](https://github.com/sonia6891/InvestToGo/actions/runs/38792912016) 使用來源 `e5fc6a1333e98193ec25c18900d141585eebbd4e`：Xcode 26.6 **編譯成功**、**29 項單元測試與 4 項 UI 測試全部通過**，五個分頁的模擬器截圖已查看，與範本一致。
- App 圖示改用 `AppIcon.appiconset/AppIcon.png`（藍底口袋圖，即 0.2.0 在 TestFlight 上的圖示）；兩個 workflow 不再用 `pocket.png` 覆蓋 AppIcon.png。網頁版主畫面圖示也改用同一張。外觀預設淺色。
- **尚未簽署上傳。** 本程式庫沒有 Apple 簽署 Secrets（testflight.yml 的 prerequisites 列出 7 項缺少）；0.2.0 是由私人程式庫 meow-work-app 的 `etftogo-archive.yml`（分支 `codex/etftogo-signing-check-20261015`）簽署上傳，該流程仍受帳戶 Actions 月預算限制。使用者選擇等 2026-11-01 額度重置後再上傳；屆時須更新該流程的來源壓縮檔與釘選 commit，並移除其中用 `pocket.png` 覆蓋 AppIcon.png 的 `sips` 那一行。

- 依「ETF 袋著走」設計稿重做五個分頁、ETF 詳情、配息月曆與工具頁，並新增領息目標、提醒中心（本機通知）、三檔比較、篩選、隱藏金額及報價開高低量。功能與資料串接說明見 README。
- 此改版在沒有 Xcode 的 Windows 環境撰寫，**只做過 Swift 語法剖析（tree-sitter，0 錯誤），尚未經 Xcode 編譯、單元測試或 UI 測試。** UI 測試已依新分頁名稱（探索、持有）、詳情分頁（持股、走勢、資訊）與按鈕文字（新增配息紀錄）更新。
- 新增 Theme.swift、DiscoverViews.swift，已同時加入 project.yml 來源資料夾與 ETFToGo.xcodeproj。
- 2026-10-15 依 Figma 設計稿（https://www.figma.com/design/ivdDhUgFxIzInvJzFZ7KgM）再對齊：Figma AI 插圖放入 Assets.xcassets/Art、上漲綠下跌紅、持有頁「交易紀錄」分頁（新增 `Portfolio.trades`，舊檔沒有此欄位仍可讀取）、詳情風險標示、App 圖示換成白底口袋圖。同樣只做過 tree-sitter 語法剖析（0 錯誤），**尚未編譯或測試**；新增單元測試 `testTradeLogRecordsHoldingChanges`，UI 測試改點「交易紀錄」與「資產配置」。網頁版已同步發佈。
- 2026-10-16 依五張範本（30 個畫面）再改版：新增 HomeScreens.swift、DividendScreens.swift、OfficialData.swift 與 official-dividends.json（已加入 ETFToGo.xcodeproj），重寫首頁、探索、持有、配息、工具與多個內頁，加入懸浮導覽列、深色模式、買進／賣出交易、配息明細與官方配息資料。**仍未編譯**：tree-sitter 語法剖析 0 錯誤，另由獨立審查逐檔比對名稱、參數與型別，未發現確定的編譯錯誤。UI 測試改用 `tab-首頁` 等導覽按鈕識別碼；新增 `testBuyAndSellAdjustHolding`、`testOfficialDistributionHelpers` 單元測試。
- 2026-10-15 Tuist Runners 檢查：GitHub 連結（etftogo ↔ sonia6891/ETFToGo）與 `tuist-macos` 規格均已設定，工作會送進 Tuist；但 macOS 工作在 Tuist 佇列中未被任何機器認領（[run 38680144589](https://github.com/sonia6891/InvestToGo/actions/runs/38680144589) 排隊 5 小時後取消、[run 38715224691](https://github.com/sonia6891/InvestToGo/actions/runs/38715224691) 仍在排隊）。Linux 測試工作在 Tuist 顯示已認領，但 GitHub 端 12 分鐘仍未取得 runner。sonia6891 是個人帳號，而 Tuist 文件要求連結 GitHub organization，推測與此有關，需向 Tuist 確認。

## 0.3.0 開發中，尚未發佈

- [上一輪原生編譯與測試](https://github.com/sonia6891/InvestToGo/actions/runs/38673558659)使用來源 `4fba133bc226d4481a9a0aee454b4342ac27fe0a`：編譯成功、五分頁截圖已查看；26 項單元測試及 3 項 UI 測試通過。另一項 UI 測試未找到獨立的 `0.22%` 文字元件，失敗截圖確認該值確實顯示在費率頁。
- 來源 `79464ec8c36fe8912b83fd6f96c1e5fc4dd5b6f0` 已明確指定費率欄的輔助使用標籤與值，修正 UI 檢查並移除年份千分位。**這次修正尚未重新編譯及驗證。**
- [重跑紀錄](https://github.com/sonia6891/InvestToGo/actions/runs/38675740702)：尚未啟動 Mac 建置機即被 GitHub 拒絕；帳戶 Actions 預算顯示 US$20 / US$20、Usage blocked。不是新的編譯結果。
- 尚未為 0.3.0 執行簽署封存或上傳 Apple；不把上一版安裝或富果測試當成本版驗證。通過完整測試後才會發佈。
- CSV 匯入測試檔及驗收步驟已準備；券商自動同步依使用者決定暫緩。0.3.0 功能及缺口見 FEATURE_GAP_AUDIT.md。

以下為 **0.2.0（2.3）的歷史發佈證據**，不是 0.3.0 的成果。

## 已完成發佈與安裝

- App Store Connect 已建立「ETF 袋著走」，App ID `6822974128`，Bundle ID `com.sonia.etftogo`，SKU `ETFTOGO-IOS-001`，主要語言為繁體中文。
- 原生 iPhone 版本 **0.2.0（2.3）** 已完成簽署、封存、匯出，於 2026-10-15 09:59 成功上傳 Apple。上傳紀錄明確顯示 `Upload succeeded`。
- Apple 處理狀態為 `VALID`，內部測試狀態為 `IN_BETA_TESTING`。建置 ID：`d7fe4f43-8762-46c6-82e1-7654ac055128`。
- 已加入「ETF ToGo 內部測試」群組；網站顯示 1 位測試人員、1 個建置版本及「正在測試」。已設定測試版介紹與意見回饋信箱。
- **使用者已在本對話回報「已安裝，能開啟」。** 這是使用者對實體 iPhone 安裝及啟動的確認；尚未代表所有功能都已完成實機驗證。
- 本次為 TestFlight 內部測試，沒有建立公開加入連結，也沒有提交 App Store 正式版審查。

## 測試與可重查的證據

- [原生編譯與測試](https://github.com/sonia6891/InvestToGo/actions/runs/38668396989)：成功。iPhone 17 Pro / iOS 26.4.1 模擬器完成五頁截圖、6 項單元測試及 2 項 UI 測試，全部零失敗。包含損壞資料原始位元組匯出、搜尋鍵盤收起，以及持有資料重新啟動後保留。
- [簽署、封存、匯出及上傳](https://github.com/sonia6891/meow-work-app/actions/runs/38668432671)：全部成功。工具為 Xcode 26.6 (17F113) / iOS 26.5 SDK，最低 iOS 17，arm64 iPhone 原生程式。
- [Apple 處理狀態查核](https://github.com/sonia6891/meow-work-app/actions/runs/38669200605)，第 2 次執行成功：上傳狀態 `COMPLETE`、處理狀態 `VALID`、內部測試狀態 `IN_BETA_TESTING`；`usesNonExemptEncryption=false`。
- 編譯與封存來源：`f2b6008573c5f9b0d768dd362394b06ca5347f9d`。後續提交僅更新交付紀錄與通用發佈流程，不更動此次已測試的 App 原始碼。
- IPA SHA-256：`3daf115937af67db277ec2c87e4a3538a67946a276a47bb87202db72791da951`。
- `Evidence/` 保存當次編譯與測試、封存、匯出、上傳紀錄，以及 Apple API 狀態、IPA 檢查結果和使用者安裝回報。
- `Screens/screen-0.png` 至 `screen-4.png` 為此次原生模擬器的五個分頁截圖，使用明確標示的示範資料。首頁截圖上方出現模擬器的 Apple Intelligence 系統通知，保留原始輸出未修圖；`overview.png` 是先前相同 SwiftUI 畫面的總覽。

## 工程與簽署設定

- 正式 Apple Bundle 資源 ID：`465MBRR9MN`。專用 App Store profile：`M8Z48T98CP`，狀態 ACTIVE，有效至 2027-09-30。
- App、單元測試與 UI 測試目標均明確指定 iPhone 裝置家族；實際 IPA 驗證 `UIDeviceFamily=[1]`，並檢查 Bundle ID、圖示、原生執行檔與 embedded provisioning profile。
- 前次 2.2 上傳被 Apple 90474 拒絕，原因是 XcodeGen 的目標層級預設值導致 IPA 包含 iPad，但僅設定直向。2.3 已修正目標層級設定並加入封存及 IPA 防回歸檢查，Apple 已接受此建置。
- 成功使用既有簽署環境的獨立分支：`sonia6891/meow-work-app` 的 `codex/etftogo-signing-check-20261015`。輸入為固定版本 ETF 原生來源 ZIP；未改動該 App 主分支，也未把簽署秘密匯出到本機或 ETF 倉庫。
- ETF 倉庫保留通用發佈流程；若後續改從 ETF 倉庫直接簽署，仍需配置其專屬 repository secrets。此次成功發佈使用的是上述已有簽署權限的 CI。

## 這版的功能與限制

- 五個原生分頁：首頁、找 ETF、我的持有、配息、工具。支援持有新增／編輯／刪除、配息記錄、收藏、比較、試算、備份及富果金鑰設定。
- 正常啟動為空資料。`--demo` 使用示範數字，且不寫入使用者正式資料。
- 內建 6 檔起始清單，並非完整台灣 ETF 名單。
- 原生 JSON 存檔採原子寫入，壞檔不覆寫；匯出會保留損壞檔原始位元組。本版 schema 1 備份尚不相容舊 PWA 備份。
- 富果使用官方 HTTP API，個人金鑰存於 Keychain；使用者已在本對話確認 0.2.0 App 取得 0050 真實報價，未將金鑰提供給建置環境。報價缺失時不會用成本假裝市值。
- 配息由使用者記錄，區分已入帳、已公告、預估，尚未串接自動公告。
- 成分股穿透、完整費用率與歷史績效尚未實作。
- App Icon 沿用既有 512 × 512 圖案，1024 × 1024 版本為等比放大，已成功納入 Apple 接受的建置。
