import Foundation
import CryptoKit

enum StableID {
    static func make(_ namespace: String, _ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data((namespace + "\u{0}" + value).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
struct LegacyPlan: Codable {
    var principal: Double
    var monthly: Double
    var years: Int
    var totalReturn: Double
    var distributionRate: Double
    var frequency: Int
    var reinvest: Double
    var deductionRate: Double
    func validate() throws {
        guard principal.isFinite, (0...1e12).contains(principal), monthly.isFinite, (0...1e9).contains(monthly), (1...50).contains(years), totalReturn.isFinite, (-0.9...0.5).contains(totalReturn), distributionRate.isFinite, (0...0.3).contains(distributionRate), [1,2,4,12].contains(frequency), reinvest.isFinite, (0...1).contains(reinvest), deductionRate.isFinite, (0...0.2).contains(deductionRate) else { throw StoreError.unsupportedBackup }
    }
}
enum BackupImport {
    struct OldHolding: Decodable { let id: String; let code: String; let name: String; let shares: Double; let cost: Double; let price: Double?; let priceDate: String? }
    struct OldDividend: Codable {
        let id: String; let code: String; let name: String; let paymentDate: String; let exDate: String?
        let eligibleShares: Double; let perShare: Double; let deductions: Double; let status: String; let actualReceived: Double?; let sourceUrl: String?
        var amount: Double { status == "received" ? (actualReceived ?? 0) : eligibleShares * perShare - deductions }
        func validate() throws {
            guard eligibleShares.isFinite, eligibleShares > 0, eligibleShares <= 1e10, eligibleShares.rounded() == eligibleShares,
                  perShare.isFinite, (0...1e5).contains(perShare), deductions.isFinite, (0...(eligibleShares * perShare)).contains(deductions),
                  status != "received" || actualReceived != nil, actualReceived.map({ $0.isFinite && (0...1e15).contains($0) }) ?? true,
                  !name.isEmpty, name.count <= 120 else { throw StoreError.unsupportedBackup }
            if let exDate { guard DataChecks.date(exDate) != nil, exDate <= paymentDate else { throw StoreError.unsupportedBackup } }
            if let sourceUrl, !sourceUrl.isEmpty { guard sourceUrl.count <= 2048, let u = URL(string: sourceUrl), ["http", "https"].contains(u.scheme), u.host != nil, u.user == nil, u.password == nil else { throw StoreError.unsupportedBackup } }
        }
    }
    struct Planning: Decodable { let version: Int; let holdings: [OldHolding]; let dividends: [OldDividend]; let plan: LegacyPlan? }
    struct Envelope: Decodable { let app: String; let version: Int; let planning: Planning; let favorites: [String]; let comparison: [String]; let components: [String: ComponentSnapshot]? }
    static func decode(_ bytes: Data) throws -> Portfolio {
        guard bytes.count <= 5_000_000, let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw StoreError.unsupportedBackup }
        if root["schema"] != nil { return try Portfolio.decodeBackup(bytes) }
        let decoder = JSONDecoder(); let planning: Planning
        var result = Portfolio()
        if root["app"] != nil {
            let old = try decoder.decode(Envelope.self, from: bytes)
            guard (old.app == "ETF_CLASSIFIER" && old.version == 3) || (old.app == "ETF_TOGO_NATIVE" && old.version == 1), old.favorites.count <= 1000, old.comparison.count <= 3, old.favorites.allSatisfy(DataChecks.code), old.comparison.allSatisfy(DataChecks.code) else { throw StoreError.unsupportedBackup }
            planning = old.planning; result.favorites = Set(old.favorites); result.comparison = old.comparison; result.components = old.components
        } else { planning = try decoder.decode(Planning.self, from: bytes) }
        guard planning.version == 2, planning.holdings.count <= 10000, planning.dividends.count <= 50000,
              Set(planning.holdings.map(\.id)).count == planning.holdings.count,
              Set(planning.dividends.map(\.id)).count == planning.dividends.count else { throw StoreError.unsupportedBackup }
        result.legacyPlan = planning.plan
        for h in planning.holdings {
            guard !h.id.isEmpty, h.id.count <= 80, DataChecks.code(h.code), !h.name.isEmpty, h.name.count <= 120, h.shares.isFinite, h.shares > 0, h.shares <= 1e10, h.cost.isFinite, (0...1e13).contains(h.cost) else { throw StoreError.unsupportedBackup }
            let id = UUID(uuidString: h.id) ?? StableID.make("legacy-holding", h.id)
            result.holdings.append(Holding(id: id, symbol: h.code, name: h.name, shares: h.shares, unitCost: h.cost / h.shares, broker: "舊版匯入（券商未記錄）", strategy: .unclassified))
            // User-entered reference prices are preserved separately, never promoted to a verified live quote.
            if let price = h.price {
                guard price.isFinite, price >= 0, let day = h.priceDate, DataChecks.date(day) != nil else { throw StoreError.unsupportedBackup }
                if result.legacyPrices == nil { result.legacyPrices = [:] }
                result.legacyPrices?[h.id] = LegacyPrice(symbol: h.code, price: price, date: day)
            }
        }
        let statuses: [String: DividendStatus] = ["received": .paid, "announced": .announced, "planned": .estimated]
        for d in planning.dividends {
            try d.validate()
            guard !d.id.isEmpty, d.id.count <= 80, DataChecks.code(d.code), let date = DataChecks.date(d.paymentDate), let status = statuses[d.status], d.amount.isFinite, d.amount >= 0 else { throw StoreError.unsupportedBackup }
            result.dividends.append(Dividend(id: UUID(uuidString: d.id) ?? StableID.make("legacy-dividend", d.id), symbol: d.code, date: date, amount: d.amount, status: status))
            if result.legacyDividends == nil { result.legacyDividends = [:] }; result.legacyDividends?[d.id] = d
        }
        _ = try Portfolio.decodeBackup(JSONEncoder().encode(result)); return result
    }
}
struct LegacyPrice: Codable { var symbol: String; var price: Double; var date: String }
