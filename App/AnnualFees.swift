import Foundation

struct AnnualExpense: Codable {
    var symbol: String
    var fundID: String
    var fundName: String
    var year: Int
    var commission: Double
    var tax: Double
    var subscriptionOffset: Double
    var management: Double
    var custody: Double
    var guarantee: Double
    var other: Double
    var total: Double
    func validate() throws {
        guard DataChecks.code(symbol), fundID.range(of: "^[0-9]{8}$", options: .regularExpression) != nil,
              !fundName.isEmpty, year >= 1990, year < Calendar.current.component(.year, from: Date()),
              [commission,tax,subscriptionOffset,management,custody,guarantee,other,total].allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { throw AppDataError("年度費用資料格式不正確。") }
    }
}
struct AnnualFeeCatalog: Codable {
    var fetchedDay: String
    var sourceURL: String
    var records: [String: AnnualExpense]
    static let bundled: AnnualFeeCatalog? = {
        guard let url = Bundle.main.url(forResource: "annual-fees", withExtension: "json"), let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(Self.self, from: data), DataChecks.date(result.fetchedDay) != nil,
              result.sourceURL == "https://www.sitca.org.tw/ROC/Industry/IN2211.aspx?pid=IN2222_01",
              result.records.allSatisfy({ $0.key == $0.value.symbol && (try? $0.value.validate()) != nil }) else { return nil }
        return result
    }()
}
