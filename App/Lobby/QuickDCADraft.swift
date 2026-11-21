import Foundation

/// What the 記一筆 sheet shows and edits before a quick DCA is saved.
struct QuickDCADraft: Equatable {
    var symbol: String
    var amount: Int?
    var shares: Int?
    var date: Date
    var broker: String
    var closeNote: String?
}

extension PortfolioStore {
    /// The sheet's starting values: the last quick DCA, else what onboarding asked, else the latest held buy.
    /// Shares are estimated in whole shares from the latest close.
    func quickDCADraft(now: Date = Date(), defaults: UserDefaults = .standard) -> QuickDCADraft {
        let start = QuickDCA.defaults(preset: data.quickDCA, onboardingSymbol: defaults.string(forKey: Onboarding.symbolKey), onboardingMonthly: Onboarding.monthlyDefault(defaults), portfolio: data)
        let symbol = start.symbol ?? ""
        let latest = quote(symbol)
        let shares = QuickDCA.estimatedShares(amount: start.amount, close: latest?.price)
        let note = shares == nil ? nil : latest.flatMap { QuickDCA.closeNote(day: $0.date) }
        return QuickDCADraft(symbol: symbol, amount: start.amount, shares: shares, date: now, broker: start.broker, closeNote: note)
    }

    /// A code the app can name: in the fund list, or already held.
    func quickDCAKnows(_ symbol: String) -> Bool {
        funds.contains { $0.id == symbol } || data.holdings.contains { $0.symbol == symbol }
    }

    /// Saves the draft as a buy through `applyTrade` (merge into the holding, record the DCA month) and remembers it as the preset.
    func logQuickDCA(_ draft: QuickDCADraft, now: Date = Date()) throws {
        if let problem = QuickDCA.problem(known: quickDCAKnows(draft.symbol), shares: draft.shares, amount: draft.amount) {
            throw AppDataError(problem.message ?? "請填寫股數與成交金額。")
        }
        guard let amount = draft.amount, let shares = draft.shares else { throw AppDataError("請填寫股數與成交金額。") }
        let broker = draft.broker.trimmingCharacters(in: .whitespacesAndNewlines)
        try applyTrade(.buy, symbol: draft.symbol, date: draft.date, shares: Double(shares), amount: Double(amount), broker: broker, logBuy: true, now: now,
                       quickDCA: QuickDCAPreset(symbol: draft.symbol, amount: amount, broker: broker))
    }
}
