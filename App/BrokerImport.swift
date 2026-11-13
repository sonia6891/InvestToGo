import Foundation

extension PortfolioStore {
    func importBroker(_ preview: BrokerPreview, replaceAccount: Bool, now: Date = Date()) throws {
        var next = data
        // A position whose row was skipped stays as last imported rather than disappearing.
        if replaceAccount { next.holdings.removeAll { $0.sourceAccount == preview.sourceAccount && !preview.skippedCodes.contains($0.symbol) } }
        for holding in preview.holdings {
            if let i = next.holdings.firstIndex(where: { $0.id == holding.id }) { next.holdings[i] = holding } else { next.holdings.append(holding) }
            next.log(.brokerImport, holding)
        }
        // A statement imported over the holdings is a reconciliation: 對帳 experience once a day, and the quest.
        if !preview.holdings.isEmpty {
            var game = next.game ?? GameState()
            _ = game.reconcile(now: now)
            next.game = game
        }
        try saveRecovery(); try commit(next)
    }
}
