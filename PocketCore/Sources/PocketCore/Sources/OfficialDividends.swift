import Foundation

public struct ExDividendNotice: Codable, Equatable {
    public enum Kind: String, Codable { case cash = "息", stock = "權", both = "權息" }
    public var symbol: String
    public var name: String
    public var exDate: String
    public var kind: Kind
    /// nil when the exchange has not published the cash amount yet; never treated as zero.
    public var cashPerShare: Double?
    public init(symbol: String, name: String, exDate: String, kind: Kind, cashPerShare: Double?) {
        self.symbol = symbol; self.name = name; self.exDate = exDate; self.kind = kind; self.cashPerShare = cashPerShare
    }
}

/// TWSE ex-rights / ex-dividend pre-announcements (TWT48U), free and key-less.
public enum OfficialDividends {
    public static let twt48uURL = "https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL"

    public static func decodeTWT48U(_ bytes: Data, etfCodes: Set<String>) throws -> [ExDividendNotice] {
        let rows = try JSONDecoder().decode([[String: String]].self, from: bytes)
        var notices: [ExDividendNotice] = []
        for row in rows {
            guard let code = row["Code"]?.trimmingCharacters(in: .whitespaces), etfCodes.contains(code) else { continue }
            guard let raw = row["Date"], raw.allSatisfy(\.isNumber), let day = DataChecks.rocDay(raw),
                  let kind = ExDividendNotice.Kind(rawValue: row["Exdividend"]?.trimmingCharacters(in: .whitespaces) ?? "") else {
                throw AppDataError("除權息資料欄位改變，未更新。")
            }
            let cashText = row["CashDividend"]?.trimmingCharacters(in: .whitespaces) ?? ""
            let cash = cashText.isEmpty ? nil : Double(cashText)
            if !cashText.isEmpty, cash.map({ !$0.isFinite || $0 < 0 }) ?? true { throw AppDataError("除權息資料欄位改變，未更新。") }
            notices.append(ExDividendNotice(symbol: code, name: row["Name"] ?? code, exDate: day, kind: kind, cashPerShare: cash))
        }
        return notices.sorted { ($0.exDate, $0.symbol) < ($1.exDate, $1.symbol) }
    }
}
