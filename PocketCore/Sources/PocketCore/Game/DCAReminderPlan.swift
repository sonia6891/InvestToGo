import Foundation

/// What the schedule depends on; any change means the pending reminders must be replaced.
struct DCAReminderInputs: Equatable {
    var day: Int
    var minutes: Int
    var dayBefore: Bool
    var showAmount: Bool
    var amount: Int?
    var symbol: String?
    /// `YearMonth(now).key`, so a new month is a new task id.
    var month: String
    var loggedThisMonth: Bool
}

struct DCAReminderRequest: Equatable {
    var id: String
    var fire: Date
    var title: String
    var body: String
    var userInfo: [String: String]
}

/// Twelve months of one-shot reminders; this month is skipped once its DCA is logged.
enum DCAReminderPlan {
    static let prefix = "dca-reminder"
    /// Ids of the old repeating reminders, removed when the one-shot schedule takes over.
    static let legacyIDs = ["dca-reminder", "dca-reminder-eve"]

    static func requests(_ inputs: DCAReminderInputs, now: Date, calendar: Calendar = GameRules.taipei) -> [DCAReminderRequest] {
        let current = YearMonth(now, calendar: calendar)
        // A debit day past the month's end (e.g. 31 in February) falls on its last day.
        func debit(in month: YearMonth) -> Date? {
            guard let first = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)),
                  let length = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
            let day = min(max(inputs.day, 1), length)
            return calendar.date(from: DateComponents(year: month.year, month: month.month, day: day,
                                                      hour: inputs.minutes / 60, minute: inputs.minutes % 60))
        }
        var start = current
        if inputs.loggedThisMonth || (debit(in: current).map { $0 <= now } ?? true) { start = current.next() }

        let known = inputs.amount != nil && inputs.symbol != nil
        let amount = inputs.amount.map(QuickDCA.amountText) ?? ""
        let route = ["route": "quickDCA"]
        let dayTitle: String, dayBody: String, eveTitle = "定期定額提醒", eveBody: String
        if known && inputs.showAmount {
            dayTitle = "今天扣款日"
            dayBody = "每月 \(amount) 元・\(inputs.symbol ?? "")，記一筆讓連續定投接下去"
            eveBody = "明天扣款日，帳戶記得留 \(amount) 元"
        } else if known {
            dayTitle = "今天扣款日"
            dayBody = "記得確認定期定額"
            eveBody = "明天扣款日，記得確認定期定額"
        } else {
            dayTitle = "定期定額提醒"
            dayBody = "今天是每月 \(inputs.day) 日的扣款日，記得確認定期定額。"
            eveBody = "明天是每月 \(inputs.day) 日的扣款日。"
        }

        var out: [DCAReminderRequest] = []
        var month = start
        for _ in 0..<12 {
            if let fire = debit(in: month) {
                if fire > now {
                    out.append(DCAReminderRequest(id: "\(prefix)-\(month.key)", fire: fire, title: dayTitle, body: dayBody, userInfo: route))
                }
                if inputs.dayBefore, let eve = calendar.date(byAdding: .day, value: -1, to: fire), eve > now {
                    out.append(DCAReminderRequest(id: "\(prefix)-eve-\(month.key)", fire: eve, title: eveTitle, body: eveBody, userInfo: route))
                }
            }
            month = month.next()
        }
        return out.sorted { $0.fire < $1.fire }
    }
}
