import Foundation
import PocketCore

extension PortfolioStore {
    func importBroker(_ preview: BrokerPreview, replaceAccount: Bool) throws {
        var next = data
        if replaceAccount { next.holdings.removeAll { $0.sourceAccount == preview.sourceAccount } }
        for holding in preview.holdings {
            if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) { next.holdings[i] = holding } else { next.holdings.append(holding) }
        }
        try saveRecovery(); try commit(next)
    }
}
