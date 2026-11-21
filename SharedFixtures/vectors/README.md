# 共用測試向量（iPhone 與 Android）

每個向量檔是一個 JSON 物件，最上層有 `kind`，例如：

```json
{
  "kind": "GameRules.level",
  "platforms": ["swift", "kotlin"],
  "cases": [
    { "name": "zero-xp-is-level-1", "input": { "xp": 0 }, "expected": 1 }
  ]
}
```

- `kind`：被測的 Swift 函式完整名稱（`型別.成員`）。同一個 kind 只能有一個檔案。
- `platforms`：省略時兩邊都要跑。只有 `format.*` 是 `["kotlin"]`：數字格式依裝置語系，Linux 記錄器的語系不能代表 iPhone，所以預期值依 iPhone 在繁體中文（台灣）設定下的顯示手寫。
- `expected`：由 Swift 記錄（`RECORD_VECTORS=1 swift test --package-path PocketCore --filter VectorTests`）。這一步在 GitHub Actions 的 `record-vectors` 工作執行，結果放在 artifact `vectors`。新增 case 時只寫 `input`。
- 會丟錯時，`expected` 是 `{"error": "<錯誤文字>"}`。錯誤文字是 iPhone 給人看的那句；不是給人看的錯誤（例如 JSON 解不開）寫成 `{"error": "*"}`。
- 輸入要讀檔時寫 `{"file": "<相對 SharedFixtures 的路徑>"}`。
- 時間一律是 ISO-8601 字串，例如 `"2026-11-22T09:00:00+08:00"`。
- 輸出裡的集合一律先排序。
- 數字比對容許 `max(1e-9, 1e-12 × 較大的絕對值)` 的誤差；其他值必須完全相同。
- 最上層沒有 `kind` 的 JSON 檔（例如備份樣本）是輸入資料，不是向量。
