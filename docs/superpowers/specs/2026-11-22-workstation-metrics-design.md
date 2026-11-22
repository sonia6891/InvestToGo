# 投資袋著走接上產品工作站（短設計）

Owner decisions, 2026-11-22:
- 「跟喵的要上班了一樣接我們後方的雲端（Supabase）…跟那個產品工作站功能接一下吧」
- 「完全比照喵的要上班了的方式」

## Intent

The owner reads downloads, subscriptions, cancellations, revenue, version use, retention and bugs for every app in the 產品工作站 (https://sonia6891.github.io/product-workstation/). 投資袋著走 is not there yet. Connect it the same way 「喵的，又要上班了」 is connected, so its numbers show on the overview, in 退訂紀錄 and in the LINE daily and weekly reports.

## Approaches

1. **Its own Supabase project, like meow-work.** The project `investtogo` would hold the app's own tables and push to the workstation every minute, with `workstation.push()` and pg_cron. It costs US$10 a month for the extra project. The owner asked to use an existing project instead: 「可以用別的專案去找嗎」.
2. **In the existing workstation project. Chosen.** It works like 額度雷達: the app's anonymous events and Apple's notifications go straight to the workstation project, through `private.app_events` and the `app-store-notifications` function. It costs nothing extra. The meow-work items below are copied into this path:
   - a `daily_open` event kind feeds version use and retention, as meow-work's `app_daily_opens` does;
   - subscription notification types feed new subscriptions, renewals, cancellations and refunds, as meow-work's `store_subscription_events` does.
3. **Apple data only, no app change.** It has no version use and no retention.

## What gets copied from meow-work

| meow-work | 投資袋著走 |
|---|---|
| `app_daily_opens` and the RPC `meow_daily_open`: anonymous install code, day, platform, version, language, country; 13-month retention; the 「傳送匿名使用統計」 switch | The same table and RPC (`investtogo_daily_open`). It is written once a day from the SwiftUI app. Same switch, under 設定 › 隱私. |
| `store_subscription_events` and the edge function `app-store-notifications-v2` (Apple V2, signature verified, Production and Sandbox) | The same table and function for `com.sonia.etftogo`, with the product `tw.sonia.etftogo.member.pocket.monthly`. |
| `appAccountToken` = account id, to tie a store event to a version | `appAccountToken` = the anonymous install code (a UUID). This gives "關閉自動續訂的人用哪一版" without an account. |
| `asc_report_rows` (Apple daily sales reports, whole developer account) | Already fetched by meow-work. Add App Store ID 6822974128 to `workstation.export_linked_store()` and `private.store_report_links`, as is done for 額度雷達. |
| `workstation` schema, `push-common.sql`, `export_rows` / `export_events` / `export_usage`, cron jobs `workstation-push-live`, `-full`, `-usage` | The same, with the product `investtogo` and its own push key. |
| Sentry → Bug 追蹤 (`sentry-sync` SOURCES) | Add the existing 投資袋著走 Sentry project. |
| Google Play RTDN and `play_install_rows` | Later, once the Android app is on Google Play. |

## Not copied (needs an account the app does not have)

- 挽回信 (winback email): there is no email to write to. 退訂紀錄 still lists each cancellation, with its version and amount paid.
- Account-level usage after cancelling, and referral codes.

## Privacy

- The app sends only the anonymous install code, platform, app version, language and country, once a day, and the install code on a purchase. It never sends holdings, amounts, trades or ETF lists.
- The 「傳送匿名使用統計」 switch is on by default, as in meow-work. Turned off, nothing is sent.
- **Update before release:**
  - The privacy policy on the official site (investtogo.pocketjoystudio.com/privacy/).
  - `PrivacyInfo.xcprivacy`: Product Interaction, not linked, not tracking, analytics.
  - The App Store privacy label.
  - The store review notes, which say "All user data stays on the device".
- This replaces the earlier rule 「App 的網路請求只帶 ETF 代碼與日期」. The owner decided it on 2026-11-22.

## Steps

1. Create the Supabase project `investtogo` (owner confirms the US$10 a month first).
2. Migrations: `app_daily_opens` and its RPC, `store_subscription_events`, the `workstation` schema and the exports. Push key on both sides.
3. Edge function `app-store-notifications-v2`, then set the URL in App Store Connect (production and sandbox).
4. App: the daily open ping, the switch, the install code as `appAccountToken`, the privacy manifest, with tests on CI.
5. Workstation: the product entry, the linked store report for 6822974128, the Sentry source.
6. Privacy policy and App Store label: show the text to the owner before publishing.

## Tests

- **Unit:**
  - The ping is sent at most once a local day.
  - Nothing is sent with the switch off.
  - Nothing is sent under `--ui-testing`.
  - The install code is stable, and `appAccountToken` equals it.
- **SQL:** the RPC rejects a malformed code; anon cannot read either table.
- **End to end:** a sandbox purchase on TestFlight appears in 退訂紀錄 after it is cancelled.
