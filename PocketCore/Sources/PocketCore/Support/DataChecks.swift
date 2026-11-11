import Foundation

struct AppDataError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
enum DataChecks {
    static func code(_ value: String) -> Bool { value.range(of: "^[0-9]{4,6}[A-Z]?$", options: .regularExpression) != nil }
    // Reused because validation and charts parse thousands of dates; DateFormatter is thread-safe on iOS 7+.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Taipei"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }()
    static func day(_ date: Date = Date()) -> String { formatter.string(from: date) }
    static func date(_ text: String) -> Date? {
        guard let value = formatter.date(from: text), formatter.string(from: value) == text else { return nil }
        return value
    }
    static func rocDay(_ text: String) -> String? {
        let raw = text.filter(\.isNumber)
        guard raw.count == 7 || raw.count == 8, let year = Int(raw.dropLast(4)) else { return nil }
        let value = String(year + (raw.count == 7 ? 1911 : 0)) + "-" + raw.dropLast(2).suffix(2) + "-" + raw.suffix(2)
        return date(value) == nil ? nil : value
    }
    /// JSON array rows; a UTF-8 byte-order mark is dropped first.
    static func jsonRows(_ bytes: Data) -> [[String: Any]]? {
        var data = bytes
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }
}
