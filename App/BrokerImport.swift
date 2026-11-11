import Foundation

extension PortfolioStore {
    func importBroker(_ preview: BrokerPreview, replaceAccount: Bool) throws {
        var next = data
        // A position whose row was skipped stays as last imported rather than disappearing.
        if replaceAccount { next.holdings.removeAll { $0.sourceAccount == preview.sourceAccount && !preview.skippedCodes.contains($0.symbol) } }
        for holding in preview.holdings {
            if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) { next.holdings[i] = holding } else { next.holdings.append(holding) }
            next.log(.brokerImport, holding)
        }
        try saveRecovery(); try commit(next)
    }
}
