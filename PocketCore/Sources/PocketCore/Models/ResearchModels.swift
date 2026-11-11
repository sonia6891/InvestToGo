import Foundation

public struct FundComponent: Codable, Identifiable {
    public var symbol: String
    public var name: String?
    public var weight: Double
    public var id: String { symbol }
    public init(symbol: String, name: String?, weight: Double) { self.symbol = symbol; self.name = name; self.weight = weight }
}

public struct ComponentSnapshot: Codable {
    public var symbol: String
    public var date: String
    public var components: [FundComponent]
    public var source: String?
    public init(symbol: String, date: String, components: [FundComponent], source: String?) {
        self.symbol = symbol; self.date = date; self.components = components; self.source = source
    }
    public var totalWeight: Double { components.reduce(0) { $0 + $1.weight } }
    public func validate() throws {
        guard DataChecks.code(symbol), DataChecks.date(date) != nil, date <= DataChecks.day(), !components.isEmpty, components.count <= 1000,
              Set(components.map(\.symbol)).count == components.count, totalWeight > 0, totalWeight <= 101,
              components.allSatisfy({ !$0.symbol.isEmpty && $0.symbol.count <= 40 && ($0.name?.count ?? 0) <= 120 && $0.weight.isFinite && (0...100).contains($0.weight) }) else { throw AppDataError("成分資料日期、代碼或權重不正確。") }
    }
    public static func imported(_ bytes: Data, symbol: String) throws -> Self {
        guard bytes.count <= 1_000_000 else { throw AppDataError("成分檔不可超過 1 MB。") }
        var value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.symbol == symbol else { throw AppDataError("成分檔與這檔 ETF 的代碼不同。") }
        value.source = "使用者匯入；原來源：" + (value.source ?? "未提供")
        try value.validate(); return value
    }
}

public struct PricePoint: Codable, Identifiable {
    public var date: String
    public var close: Double
    public var id: String { date }
    public init(date: String, close: Double) { self.date = date; self.close = close }
}

public struct PriceHistory: Codable {
    public var symbol: String
    public var adjusted: Bool
    public var points: [PricePoint]
    public var fetchedDay: String
    public var source: String
    public init(symbol: String, adjusted: Bool, points: [PricePoint], fetchedDay: String, source: String) {
        self.symbol = symbol; self.adjusted = adjusted; self.points = points; self.fetchedDay = fetchedDay; self.source = source
    }
    public func validate() throws {
        guard DataChecks.code(symbol), adjusted, points.count >= 2, points.count <= 10000, DataChecks.date(fetchedDay) != nil,
              Set(points.map(\.date)).count == points.count,
              points.allSatisfy({ DataChecks.date($0.date) != nil && $0.date <= DataChecks.day() && $0.close.isFinite && $0.close > 0 }),
              points.map(\.date) == points.map(\.date).sorted() else { throw AppDataError("歷史資料缺失、日期重複或沒有確認還原價格，未計算績效。") }
    }
}

public struct FeeRecord: Codable {
    public var symbol: String
    public var effectiveDate: String
    public var management: String
    public var custody: String
    public var annualExpensePercent: Double?
    public var expenseYear: Int?
    public var sourceURL: String
    public var note: String
    public init(symbol: String, effectiveDate: String, management: String, custody: String, annualExpensePercent: Double?, expenseYear: Int?, sourceURL: String, note: String) {
        self.symbol = symbol; self.effectiveDate = effectiveDate; self.management = management; self.custody = custody
        self.annualExpensePercent = annualExpensePercent; self.expenseYear = expenseYear; self.sourceURL = sourceURL; self.note = note
    }
    public func validate() throws {
        guard DataChecks.code(symbol), DataChecks.date(effectiveDate) != nil, effectiveDate <= DataChecks.day(),
              !management.isEmpty, management.count <= 2000, !custody.isEmpty, custody.count <= 2000, note.count <= 2000,
              let url = URL(string: sourceURL), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw AppDataError("請填寫費率級距、有效日期及 HTTPS 資料來源。") }
        if let rate = annualExpensePercent {
            guard rate.isFinite, (0...100).contains(rate), let year = expenseYear, (1990...Calendar.current.component(.year, from: Date())).contains(year) else { throw AppDataError("總費用率須附統計年度，且數值應為 0～100%。") }
        } else if expenseYear != nil { throw AppDataError("費用年度與總費用率須一起填寫。") }
    }
}
