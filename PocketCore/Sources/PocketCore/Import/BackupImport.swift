import Foundation

public enum BackupImport {
    public struct OldDividend: Codable {
        public let id: String; public let code: String; public let name: String; public let paymentDate: String; public let exDate: String?
        public let eligibleShares: Double; public let perShare: Double; public let deductions: Double; public let status: String; public let actualReceived: Double?; public let sourceUrl: String?
        public var amount: Double { status == "received" ? (actualReceived ?? 0) : eligibleShares * perShare - deductions }
        public func validate() throws {
            guard eligibleShares.isFinite, eligibleShares > 0, eligibleShares <= 1e10, eligibleShares.rounded() == eligibleShares,
                  perShare.isFinite, (0...1e5).contains(perShare), deductions.isFinite, (0...(eligibleShares * perShare)).contains(deductions),
                  status != "received" || actualReceived != nil, actualReceived.map({ $0.isFinite && (0...1e15).contains($0) }) ?? true,
                  !name.isEmpty, name.count <= 120 else { throw StoreError.unsupportedBackup }
            if let exDate { guard DataChecks.date(exDate) != nil, exDate <= paymentDate else { throw StoreError.unsupportedBackup } }
            if let sourceUrl, !sourceUrl.isEmpty { guard sourceUrl.count <= 2048, let u = URL(string: sourceUrl), ["http", "https"].contains(u.scheme), u.host != nil, u.user == nil, u.password == nil else { throw StoreError.unsupportedBackup } }
        }
    }
}
