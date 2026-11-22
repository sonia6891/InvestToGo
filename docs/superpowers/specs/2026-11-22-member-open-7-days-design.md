# 口袋會員前 7 天全開（短設計）

Owner, 2026-11-22:
- 「評分系統有了嗎？PRO 七天全開有了嗎？」
- Earlier, about the workstation: 「完全比照喵的要上班了的方式」.

This copies 「喵的，又要上班了」's 「前 7 天 PRO 全部免費開放」. Its reference is `D:/Projects/meow-work-app/assets/meow-v4-proopen.js`, with the days kept in `index.html:7047-7140`: `FREE_TIER`, `PRO_OPEN_DAYS` and `proOpenInfo`.

## Intent

A new user gets every 口袋會員 tool free for the first 7 days, so they try the paid tools before deciding. The rating sheet already asks on day 3, on branch `claude/workstation-events`, which lines up with meow's day 3 of the 7.

## Design

**The 7 days**
- They are 7 × 24 h from the first open of this app on this phone. Day 1 is that first open.
- The start time is kept in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so deleting and reinstalling the app does not start a new 7 days. It is never in backups or exports.
- While the 7 days run, everything `MembershipStore` gates is open, exactly as for a member. That covers the member tools (回測, 存錢目標反推, 到價提醒, 口袋月報／年報, 主動式追蹤, 重疊成分) and anything else gated as member-only today.
- No payment and no store offer are involved, and nothing renews. Nothing counts down by the second.

**What the person sees**
- **大廳 banner, on every day of the 7.** One line: 「口袋會員全開中・11/29（日）14:30 結束・還剩 N 天」. Tapping it opens the 會員 page.
  - The end is stated with its time, because the 7 days are 7 × 24 h; a date alone reads as the whole day.
  - The weekday is Chinese, and the date is Gregorian in POSIX digits.
- **Day 1 note, once.** It says the 7 days started, when they end, and that every record stays afterwards; only the 口袋會員 tools lock again.
  - It shows after the opening, onboarding and the lock screen, never over them.
- **Day 5 note, once.** A gentle reminder of what stays free afterwards.
- **After day 7, if not a member, one sheet, once.** It shows what was used in the 7 days (which member tools were opened, counted on the device), the store price from StoreKit, and a button 「訂閱口袋會員」 that opens the 會員 page. A close button is also shown.
- **3 days later, once, if still not a member.** 「要不要再考慮一下口袋會員？」 opens the 會員 page. After that, nothing more is shown.
- Each note is shown once (device state, not in backups). None shows over the opening, the lock screen, onboarding, LEVEL×UP, a sheet, a purchase or an open keyboard.

**After the 7 days**
- No data is ever touched. What the person made with a member tool (a goal, a price alert, a report setting) stays saved and comes back when they subscribe.
- Price alerts stop checking until they subscribe, as for any non-member.
- A member who subscribes during the 7 days simply stays a member, with no notes.

## Constraints

- Copy in Traditional Chinese (台灣用語). Say 外觀主題, never 皮膚.
- No new packages.
- Every existing accessibility identifier keeps its name.
- New identifiers: `member-open-banner`, `member-open-note`, `member-open-summary`, `member-open-subscribe`.
- Under `--ui-testing` the 7 days are off unless `--member-open <day>` is passed, which sets which day it is (1–10). Existing UI tests that check a locked member tool keep working unchanged.
- App Review 3.1.2: the summary sheet shows the real StoreKit price and period, with the Terms and Privacy links, as the 會員 page does.

## Tests

- **Unit:**
  - Days 1–7 open and day 8 closed, with an injected clock.
  - The start survives a simulated reinstall (Keychain) and is not reset by a clock moved backwards.
  - Each note's day, and that it shows once.
  - The summary shows only to a non-member after day 7.
  - "3 days later" shows once.
- **UI:**
  - `testMemberOpenBanner`: `--member-open 2` shows `member-open-banner`, and a member tool opens without the lock card.
  - `testMemberOpenEnds`: `--member-open 8` shows the summary sheet, and the member tool is locked again.
