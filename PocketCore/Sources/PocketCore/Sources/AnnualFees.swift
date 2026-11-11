import Foundation

public struct AnnualExpense: Codable {
    public var symbol: String
    public var fundID: String
    public var fundName: String
    public var year: Int
    public var commission: Double
    public var tax: Double
    public var subscriptionOffset: Double
    public var management: Double
    public var custody: Double
    public var guarantee: Double
    public var other: Double
    public var total: Double
    public func validate() throws {
        guard DataChecks.code(symbol), fundID.range(of: "^[0-9]{8}$", options: .regularExpression) != nil,
              !fundName.isEmpty, year >= 1990, year < Calendar.current.component(.year, from: Date()),
              [commission,tax,subscriptionOffset,management,custody,guarantee,other,total].allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { throw AppDataError("年度費用資料格式不正確。") }
    }
}

public struct AnnualFeeCatalog: Codable {
    public var fetchedDay: String
    public var sourceURL: String
    public var records: [String: AnnualExpense]
    public static let bundled: AnnualFeeCatalog? = {
        guard let url = Bundle.module.url(forResource: "annual-fees", withExtension: "json"), let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(Self.self, from: data), DataChecks.date(result.fetchedDay) != nil,
              result.sourceURL == "https://www.sitca.org.tw/ROC/Industry/IN2211.aspx?pid=IN2222_01",
              result.records.allSatisfy({ $0.key == $0.value.symbol && (try? $0.value.validate()) != nil }) else { return nil }
        return result
    }()
}
