import Foundation

// 口袋會員前 7 天全開 (docs/superpowers/specs/2026-11-22-member-open-7-days-design.md), after the meow-work app's
// 「前 7 天 PRO 全部免費開放」: every 口袋會員 tool is open for 7 × 24 h from the first open of the app on this phone.
// No payment and no store offer is involved, nothing renews and nothing counts down by the second. This file holds the
// days and the notes; `MembershipStore` opens its one gate with them, and the lobby shows them.

/// What is kept about the 7 days, in one Keychain item on this device only (never in a backup or an export): a
/// reinstall reads the same start, so it never starts a new 7 days, and each note stays shown once.
struct MemberOpenRecord: Codable, Equatable {
    /// The first open of the app on this phone: day 1.
    var start: Date
    /// When each note was shown, by `MemberOpenNote.rawValue`.
    var seen: [String: Date] = [:]
    /// The member tools opened during the 7 days, by `MemberFeature.rawValue`: the summary after day 7 lists them.
    var used: [String: Int] = [:]
}

enum MemberOpenRead: Equatable {
    case found(MemberOpenRecord)
    case missing
    /// The Keychain cannot be read yet (a launch in the background before the phone's first unlock).
    case unreadable
}

/// Where the record is kept: the Keychain in the app, memory in tests.
protocol MemberOpenVault: AnyObject {
    func read() -> MemberOpenRead
    func save(_ record: MemberOpenRecord) throws
}

/// UI tests and unit tests: nothing is written to the simulator's Keychain. `record` survives as long as the object,
/// which is how a test stands in for a reinstall.
final class MemoryMemberOpenVault: MemberOpenVault {
    var record: MemberOpenRecord?
    /// Reads as `.unreadable` while true (a phone not yet unlocked since it started).
    var unreadable = false
    init(_ record: MemberOpenRecord? = nil) { self.record = record }
    func read() -> MemberOpenRead {
        if unreadable { return .unreadable }
        return record.map { .found($0) } ?? .missing
    }
    func save(_ record: MemberOpenRecord) throws { self.record = record }
}

/// The four notes, each shown once.
enum MemberOpenNote: String, CaseIterable, Identifiable {
    /// The 7 days have started: when they end, and that every record stays afterwards.
    case day1
    /// A gentle reminder of what stays free afterwards.
    case day5
    /// After day 7, to a non-member: what was used, the price and 「訂閱口袋會員」.
    case ended
    /// Three days after that, once: 「要不要再考慮一下口袋會員？」. Nothing after it.
    case again
    var id: String { rawValue }
}

/// Where the 7 days stand at a moment.
struct MemberOpenInfo: Equatable {
    static let days = 7
    static let dayLength: TimeInterval = 86_400
    static let length: TimeInterval = Double(days) * dayLength
    /// How far the phone's clock may be behind the kept start and still count as day 1.
    static let clockSlack: TimeInterval = dayLength

    var start: Date?
    var active: Bool
    var ended: Bool
    /// Day 1 to 7 while active, else 0.
    var day: Int
    /// 7 on day 1 down to 1 on day 7 (never 0 while active), else 0.
    var daysLeft: Int
    /// The phone's clock is more than a day behind the kept start: nothing is open and nothing is said until it is
    /// right again (the start itself is never moved).
    var clockBehind = false

    var end: Date? { start.map { $0.addingTimeInterval(Self.length) } }

    static let off = MemberOpenInfo(start: nil, active: false, ended: false, day: 0, daysLeft: 0)

    static func of(start: Date?, now: Date) -> MemberOpenInfo {
        guard let start else { return .off }
        var elapsed = now.timeIntervalSince(start)
        if elapsed < -clockSlack {
            return MemberOpenInfo(start: start, active: false, ended: false, day: 0, daysLeft: 0, clockBehind: true)
        }
        elapsed = max(0, elapsed)
        guard elapsed < length else { return MemberOpenInfo(start: start, active: false, ended: true, day: 0, daysLeft: 0) }
        return MemberOpenInfo(start: start, active: true, ended: false, day: Int(elapsed / dayLength) + 1,
                              daysLeft: max(1, Int(((length - elapsed) / dayLength).rounded(.up))))
    }
}

/// The 7 days on this phone: read (or started) from the vault, by an injected clock.
final class MemberOpenDays {
    /// Three days after the end, and after the summary, 「再考慮」 is shown once.
    static let againAfter: TimeInterval = 3 * MemberOpenInfo.dayLength

    private let vault: MemberOpenVault
    private let now: () -> Date
    /// A first read with nothing kept starts the 7 days (a real launch). False keeps them off: UI tests without
    /// `--member-open`, and the unit-test host.
    let starts: Bool
    /// A note missed on its own day still shows later (day 1's note until day 4). UI tests, which set the day
    /// themselves, see a note only on its own day, so one never sits over a test that is about something else.
    let catchUp: Bool
    /// The record once read or started: a Keychain that later fails to save still ends the 7 days instead of starting
    /// them again at every read.
    private var memo: MemberOpenRecord?

    init(vault: MemberOpenVault, now: @escaping () -> Date = Date.init, starts: Bool = true, catchUp: Bool = true) {
        self.vault = vault
        self.now = now
        self.starts = starts
        self.catchUp = catchUp
    }

    /// The kept record, started at the first read when none is kept. nil while the vault cannot be read, and when
    /// nothing is kept and `starts` is false.
    func record() -> MemberOpenRecord? {
        if let memo { return memo }
        switch vault.read() {
        case .found(let record):
            memo = record
            return record
        case .unreadable:
            return nil
        case .missing:
            guard starts else { return nil }
            let record = MemberOpenRecord(start: now())
            memo = record
            try? vault.save(record)
            return record
        }
    }

    func info() -> MemberOpenInfo { MemberOpenInfo.of(start: record()?.start, now: now()) }

    /// The clock the 7 days are judged by.
    var date: Date { now() }

    /// The note to show now, if any. `member`: this Apple ID holds a plan (never a note for a member).
    func due(member: Bool) -> MemberOpenNote? {
        guard !member, let record = record() else { return nil }
        let at = now(), info = MemberOpenInfo.of(start: record.start, now: at)
        func seen(_ note: MemberOpenNote) -> Date? { record.seen[note.rawValue] }
        if info.ended {
            guard let summary = seen(.ended) else { return .ended }
            // Three days after the 7 days and three days after the summary (never two on one launch), once.
            if seen(.again) == nil, let end = info.end, at.timeIntervalSince(end) >= Self.againAfter,
               at.timeIntervalSince(summary) >= Self.againAfter { return .again }
            return nil
        }
        guard info.active, seen(.ended) == nil else { return nil }
        if seen(.day5) == nil, (catchUp ? info.day >= 5 : info.day == 5) { return .day5 }
        if seen(.day1) == nil, seen(.day5) == nil, (catchUp ? info.day < 5 : info.day == 1) { return .day1 }
        return nil
    }

    /// The note is on screen: it is never shown again.
    func markSeen(_ note: MemberOpenNote) {
        update { $0.seen[note.rawValue] = now() }
    }

    /// A member (subscribed during the 7 days or before): the summary and 「再考慮」 are about a plan never bought, so
    /// they are marked seen without a word, and a subscription that lapses months later does not bring them up.
    func quietForMember() {
        guard let record = record(), record.seen[MemberOpenNote.ended.rawValue] == nil || record.seen[MemberOpenNote.again.rawValue] == nil else { return }
        update {
            let at = now()
            if $0.seen[MemberOpenNote.ended.rawValue] == nil { $0.seen[MemberOpenNote.ended.rawValue] = at }
            if $0.seen[MemberOpenNote.again.rawValue] == nil { $0.seen[MemberOpenNote.again.rawValue] = at }
        }
    }

    /// A member tool opened during the 7 days, counted on the device for the summary. Nothing outside them.
    func noteUse(_ feature: MemberFeature) {
        guard info().active else { return }
        update { $0.used[feature.rawValue, default: 0] += 1 }
    }

    /// The member tools opened during the 7 days, in `MemberFeature` order.
    func usedFeatures() -> [MemberFeature] {
        let used = record()?.used ?? [:]
        return MemberFeature.allCases.filter { (used[$0.rawValue] ?? 0) > 0 }
    }

    private func update(_ change: (inout MemberOpenRecord) -> Void) {
        guard var record = record() else { return }
        change(&record)
        memo = record
        try? vault.save(record)
    }

    // MARK: `--member-open <day>`

    /// `--ui-testing --member-open <day>` (1–10): which day of the 7 days a UI test or screenshot is on. Without it,
    /// UI tests have the 7 days off.
    static func uiTestDay(_ arguments: [String]) -> Int? {
        guard arguments.contains("--ui-testing"), let i = arguments.firstIndex(of: "--member-open"), arguments.indices.contains(i + 1),
              let day = Int(arguments[i + 1]), (1...10).contains(day) else { return nil }
        return day
    }

    /// The start that makes `now` an hour into `day`.
    static func uiTestStart(day: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(day - 1) * MemberOpenInfo.dayLength - 3_600)
    }
}

/// What the 7 days say, in Traditional Chinese (台灣用語).
enum MemberOpenCopy {
    private static let weekdays = Array("日一二三四五六")

    /// When the 7 days end, with its time (they are 7 × 24 h: a date alone reads as the whole day): 「11/29（日）14:30」,
    /// a Gregorian date in POSIX digits and the weekday in Chinese.
    static func endText(_ end: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: end)
        let weekday = weekdays[((c.weekday ?? 1) - 1 + 7) % 7]
        return "\(c.month ?? 0)/\(c.day ?? 0)（\(weekday)）" + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// The lobby's line on every day of the 7: 「口袋會員全開中・11/29（日）14:30 結束・還剩 6 天」. nil outside them.
    static func banner(_ info: MemberOpenInfo, timeZone: TimeZone = .current) -> String? {
        guard info.active, let end = info.end else { return nil }
        return "口袋會員全開中・\(endText(end, timeZone: timeZone)) 結束・還剩 \(info.daysLeft) 天"
    }

    static let day1Title = "前 7 天，口袋會員全部免費開放"
    static func day1Ends(_ end: String) -> String { "到 \(end) 結束" }
    static let noPayment = "不用付款、不會自動扣款。"
    static let day1Lead = "這 7 天，所有口袋會員工具和全部外觀主題都能用。"
    static let day1After = "7 天後，只有口袋會員工具會再鎖起來；你記下的紀錄和做好的設定都會留著。"
    static func day5Title(_ daysLeft: Int) -> String { "口袋會員全開還剩 \(daysLeft) 天" }
    static let day5Lead = "7 天過後會回到免費版，不會自動收費。免費版一樣可以："
    static let day5After = "你的資料都會保留。想繼續用全部工具，可以看看口袋會員。"
    /// What stays free afterwards (the 會員 page's free plan, said as a list).
    static let free = ["記帳與庫存", "配息紀錄與除息提醒", "ETF 圖鑑與找 ETF", "定期定額連續紀錄與任務"]
    static let endedTitle = "7 天的口袋會員全開結束了"
    static let endedUsed = "這 7 天你用過這些口袋會員工具："
    static let endedNone = "現在回到免費版：記帳、配息、提醒和圖鑑照常可以用。"
    static let endedKept = "你用口袋會員工具做好的存錢目標、到價提醒和月報設定都保留著，訂閱後馬上回來；到價提醒在那之前先暫停檢查。"
    static let againTitle = "要不要再考慮一下口袋會員？"
    static let againLead = "這幾天你用免費版。如果想念這些工具，隨時可以回來："
    static let againKept = "你的資料都還在，訂閱後馬上回來。"
    static let renews = "訂閱會自動續訂，可隨時在 App Store 的訂閱設定取消；價格以 App Store 顯示為準。"
    static let subscribe = "訂閱口袋會員"
    static let look = "看看口袋會員"
    static let start = "開始用"
    static let gotIt = "知道了"
    static let stayFree = "先用免費版"
    static let noThanks = "不用了，謝謝"
    static let close = "關閉"
    /// The tools 「再考慮」 names when none was opened in the 7 days.
    static let againDefault: [MemberFeature] = [.backtest, .goalPlanner, .priceAlerts]
    /// The notice when a 外觀主題 worn during the 7 days goes back to 黑金 at their end.
    static let skinNotice = "口袋會員全開結束，外觀主題已換回黑金"

    static var everything: [String] {
        [day1Title, day1Ends("11/29（日）14:30"), noPayment, day1Lead, day1After, day5Title(3), day5Lead, day5After, endedTitle,
         endedUsed, endedNone, endedKept, againTitle, againLead, againKept, renews, subscribe, look, start, gotIt, stayFree,
         noThanks, close, skinNotice] + free
    }
}
