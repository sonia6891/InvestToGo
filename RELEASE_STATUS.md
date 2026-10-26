# ETF 袋著走 — TestFlight 發佈紀錄

更新日期：2026-10-15（台灣時間）。唯一持續開發來源為本 SwiftUI 工程。**開發中原始碼為 0.3.0；已發佈到 TestFlight 的版本仍為 0.2.0（2.3）。**

## 0.3.0 開發中，尚未發佈

- [上一輪原生編譯與測試](https://github.com/sonia6891/ETFToGo/actions/runs/38673558659)使用來源 `4fba133bc226d4481a9a0aee454b4342ac27fe0a`：編譯成功、五分頁截圖已查看；26 項單元測試及 3 項 UI 測試通過。另一項 UI 測試未找到獨立的 `0.22%` 文字元件，失敗截圖確認該值確實顯示在費率頁。
- 來源 `79464ec8c36fe8912b83fd6f96c1e5fc4dd5b6f0` 已明確指定費率欄的輔助使用標籤與值，修正 UI 檢查並移除年份千分位。**這次修正尚未重新編譯及驗證。**
- [重跑紀錄](https://github.com/sonia6891/ETFToGo/actions/runs/38675740702)：尚未啟動 Mac 建置機即被 GitHub 拒絕；帳戶 Actions 預算顯示 US$20 / US$20、Usage blocked。不是新的編譯結果。
- 尚未為 0.3.0 執行簽署封存或上傳 Apple；不把上一版安裝或富果測試當成本版驗證。通過完整測試後才會發佈。
- CSV 匯入測試檔及驗收步驟已準備；券商自動同步依使用者決定暫緩。0.3.0 功能及缺口見 FEATURE_GAP_AUDIT.md。
- 2026-10-26 加入個股持有與三種情境試算，含新的單元及 UI 測試原始碼。**未編譯、未執行任何測試**；使用者指示先完成功能，再安排編譯。

以下為 **0.2.0（2.3）的歷史發佈證據**，不是 0.3.0 的成果。

## 已完成發佈與安裝

- App Store Connect 已建立「ETF 袋著走」，App ID `6822974128`，Bundle ID `com.sonia.etftogo`，SKU `ETFTOGO-IOS-001`，主要語言為繁體中文。
- 原生 iPhone 版本 **0.2.0（2.3）** 已完成簽署、封存、匯出，於 2026-10-15 09:59 成功上傳 Apple。上傳紀錄明確顯示 `Upload succeeded`。
- Apple 處理狀態為 `VALID`，內部測試狀態為 `IN_BETA_TESTING`。建置 ID：`d7fe4f43-8762-46c6-82e1-7654ac055128`。
- 已加入「ETF ToGo 內部測試」群組；網站顯示 1 位測試人員、1 個建置版本及「正在測試」。已設定測試版介紹與意見回饋信箱。
- **使用者已在本對話回報「已安裝，能開啟」。** 這是使用者對實體 iPhone 安裝及啟動的確認；尚未代表所有功能都已完成實機驗證。
- 本次為 TestFlight 內部測試，沒有建立公開加入連結，也沒有提交 App Store 正式版審查。

## 測試與可重查的證據

- [原生編譯與測試](https://github.com/sonia6891/ETFToGo/actions/runs/38668396989)：成功。iPhone 17 Pro / iOS 26.4.1 模擬器完成五頁截圖、6 項單元測試及 2 項 UI 測試，全部零失敗。包含損壞資料原始位元組匯出、搜尋鍵盤收起，以及持有資料重新啟動後保留。
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
