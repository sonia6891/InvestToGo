import Foundation

public struct AppDataError: LocalizedError {
    public let text: String
    public init(_ text: String) { self.text = text }
    public var errorDescription: String? { text }
}

public enum DataChecks {
    public static func code(_ value: String) -> Bool { value.range(of: "^[0-9]{4,6}[A-Z]?$", options: .regularExpression) != nil }
    public static func day(_ date: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    public static func date(_ text: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let value = formatter.date(from: text), formatter.string(from: value) == text else { return nil }
        return value
    }
    public static func rocDay(_ text: String) -> String? {
        let raw = text.filter(\.isNumber)
        guard raw.count == 7 || raw.count == 8, let year = Int(raw.dropLast(4)) else { return nil }
        let value = String(year + (raw.count == 7 ? 1911 : 0)) + "-" + raw.dropLast(2).suffix(2) + "-" + raw.suffix(2)
        return date(value) == nil ? nil : value
    }
}
