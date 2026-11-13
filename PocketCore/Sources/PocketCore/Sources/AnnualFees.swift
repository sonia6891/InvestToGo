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
    enum CodingKeys: String, CodingKey { case symbol, fundID, fundName, year, commission, tax, subscriptionOffset, management, custody, guarantee, other, total }
    func validate() throws {
        guard DataChecks.code(symbol), fundID.range(of: "^[0-9]{8}$", options: .regularExpression) != nil,
              !fundName.isEmpty, year >= 1990, year < Calendar.current.component(.year, from: Date()),
              [commission,tax,subscriptionOffset,management,custody,guarantee,other,total].allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { throw AppDataError("年度費用資料格式不正確。") }
    }
}
extension AnnualExpense {
    /// The fund name in NFC (see `Fund.init(from:)`): SITCA writes 金 and 益 as compatibility ideographs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol); fundID = try c.decode(String.self, forKey: .fundID)
        fundName = try c.decode(String.self, forKey: .fundName).nfc; year = try c.decode(Int.self, forKey: .year)
        commission = try c.decode(Double.self, forKey: .commission); tax = try c.decode(Double.self, forKey: .tax)
        subscriptionOffset = try c.decode(Double.self, forKey: .subscriptionOffset); management = try c.decode(Double.self, forKey: .management)
        custody = try c.decode(Double.self, forKey: .custody); guarantee = try c.decode(Double.self, forKey: .guarantee)
        other = try c.decode(Double.self, forKey: .other); total = try c.decode(Double.self, forKey: .total)
    }
}
struct AnnualFeeCatalog: Codable {
    var fetchedDay: String
    var sourceURL: String
    var records: [String: AnnualExpense]
    static let bundled: AnnualFeeCatalog? = {
        guard let url = CoreBundle.bundle.url(forResource: "annual-fees", withExtension: "json"), let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(Self.self, from: data), DataChecks.date(result.fetchedDay) != nil,
              result.sourceURL == "https://www.sitca.org.tw/ROC/Industry/IN2211.aspx?pid=IN2222_01",
              result.records.allSatisfy({ $0.key == $0.value.symbol && (try? $0.value.validate()) != nil }) else { return nil }
        return result
    }()
}
