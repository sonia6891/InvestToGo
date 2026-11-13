import Foundation

enum TaiwanMarket {
    static let zone = TimeZone(identifier: "Asia/Taipei")!
    static func isOpen(_ date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, (2...6).contains(weekday), let hour = parts.hour, let minute = parts.minute else { return false }
        let minutes = hour * 60 + minute
        return minutes >= 8 * 60 + 55 && minutes <= 13 * 60 + 40
    }
}

/// One aggregates push: the latest trade (or trial match) and the day's figures.
