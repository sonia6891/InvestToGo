import Foundation

/// 到價提醒 (口袋會員): one price to watch for one code. It fires once, is then switched off with the time it fired, and
/// can be switched on again by hand.
struct PriceAlert: Codable, Identifiable, Equatable {
    var id = UUID()
    var symbol: String
    /// True: the price is at or over `price`. False: at or under it.
    var above: Bool
    var price: Double
    var enabled = true
    /// When it last fired; nil until it has.
    var firedAt: Date? = nil

    var isValid: Bool { DataChecks.code(symbol) && price.isFinite && price > 0 && price <= AlertEngine.maxPrice }
    /// 「高於 200」 or 「低於 18.5」.
    var condition: String { "\(above ? "高於" : "低於") \(decimal(price))" }
}

enum AlertEngine {
    /// How many alerts may be kept, switched on or off.
    static let limit = 20
    static let maxPrice = 1_000_000.0
    /// A price whose trading day is further back than this is not judged.
    static let freshDays = 7

    /// The alerts to fire now: the enabled ones whose code has a price at or past the target. Only the latest price is
    /// compared, so a price that crossed the target and came back between two checks is not caught. A code without a
    /// price is skipped, and nothing is due for someone who is not a member.
    static func due(_ alerts: [PriceAlert], prices: [String: Double], isMember: Bool) -> [UUID] {
        guard isMember else { return [] }
        return alerts.filter { alert in
            guard alert.enabled, let price = prices[alert.symbol], price.isFinite, price > 0 else { return false }
            return alert.above ? price >= alert.price : price <= alert.price
        }.map(\.id)
    }

    /// Whether there is anything to check in the background: an enabled alert, and a member to tell.
    static func watching(_ alerts: [PriceAlert], isMember: Bool) -> Bool {
        isMember && alerts.contains { $0.enabled }
    }

    /// Whether a price of trading day `day` ("yyyy-MM-dd") is recent enough to judge an alert on. An old price (the
    /// one bundled with the app, or the last one fetched weeks ago) says nothing about today.
    static func isCurrent(day: String, now: Date) -> Bool {
        guard DataChecks.date(day) != nil else { return false }
        let oldest = GameRules.taipei.date(byAdding: .day, value: -freshDays, to: now) ?? now
        return day >= DataChecks.day(oldest)
    }

    /// The notification's words: the code, the price it reached and what was set. A fact, never advice.
    static func message(_ alert: PriceAlert, price: Double) -> String {
        "\(alert.symbol) 已到 \(decimal(price))，你設定的是\(alert.above ? "高於" : "低於") \(decimal(alert.price))。"
    }
}

extension Portfolio {
    /// Adds an alert, switched on. Throws, in the form's own words, when the list is full, the same alert is there
    /// already or the values cannot be an alert.
    @discardableResult mutating func addAlert(symbol: String, above: Bool, price: Double) throws -> PriceAlert {
        let alert = PriceAlert(symbol: symbol, above: above, price: price)
        guard alert.isValid else { throw AppDataError("請輸入正確的代號與大於 0 的價格。") }
        var list = alerts ?? []
        guard list.count < AlertEngine.limit else { throw AppDataError("最多 \(AlertEngine.limit) 個提醒，請先刪除不用的。") }
        guard !list.contains(where: { $0.symbol == symbol && $0.above == above && $0.price == price }) else { throw AppDataError("已經有一樣的提醒。") }
        list.append(alert)
        alerts = list
        return alert
    }

    /// Marks these alerts as fired at `now` and switches them off; returns them as they are now.
    @discardableResult mutating func fireAlerts(_ ids: [UUID], now: Date) -> [PriceAlert] {
        var list = alerts ?? []
        var fired: [PriceAlert] = []
        for i in list.indices where ids.contains(list[i].id) {
            list[i].enabled = false
            list[i].firedAt = now
            fired.append(list[i])
        }
        if !fired.isEmpty { alerts = list }
        return fired
    }

    /// A backup's alerts: one with a known id replaces it, a new one is added while there is room.
    mutating func mergeAlerts(_ incoming: [PriceAlert]) {
        guard !incoming.isEmpty else { return }
        var list = alerts ?? []
        for item in incoming {
            if let i = list.firstIndex(where: { $0.id == item.id }) { list[i] = item } else if list.count < AlertEngine.limit { list.append(item) }
        }
        alerts = list
    }
}
