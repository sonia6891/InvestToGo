import Foundation

/// What the lobby last showed: experience, coins and this month's ticked quests. Saved, so the next visit can
/// replay only what grew since.
struct LobbySnapshot: Codable, Equatable {
    var xp: Int
    var coins: Int
    /// `YearMonth.key` of the month `quests` belong to.
    var month: String
    var quests: Set<String>

    /// The lobby's quests that are done this Taipei month, by the same list the quest card shows.
    static func of(_ game: GameState, now: Date) -> LobbySnapshot {
        let month = YearMonth(now)
        let done = Quests.forMonth(month, habit: game.habit ?? .dca, isNewbie: game.isNewbie)
            .filter { game.isDone($0, in: month) }
            .map(\.id)
        return LobbySnapshot(xp: game.xp, coins: game.coins, month: month.key, quests: Set(done))
    }
}

/// The difference between what the lobby showed last time and what is true now.
struct LobbyReplay: Equatable {
    var newQuests: [String]
    var coinsFrom: Int
    var coinsTo: Int
    var xpFrom: Int
    var xpTo: Int
    var levelFrom: Int
    var levelTo: Int
    var crossesLevel: Bool { levelTo > levelFrom }

    /// nil when there is nothing to replay: nothing shown before, numbers that went down (an older backup was
    /// restored), or nothing that grew. Quest ticks are only compared inside the same month.
    static func between(shown: LobbySnapshot?, now: LobbySnapshot, questOrder: [String] = []) -> LobbyReplay? {
        guard let shown, now.xp >= shown.xp, now.coins >= shown.coins else { return nil }
        var fresh: [String] = []
        if shown.month == now.month {
            let added = now.quests.subtracting(shown.quests)
            fresh = questOrder.filter(added.contains) + added.subtracting(questOrder).sorted()
        }
        guard now.xp > shown.xp || now.coins > shown.coins || !fresh.isEmpty else { return nil }
        return LobbyReplay(newQuests: fresh, coinsFrom: shown.coins, coinsTo: now.coins, xpFrom: shown.xp, xpTo: now.xp,
                           levelFrom: GameRules.level(xp: shown.xp), levelTo: GameRules.level(xp: now.xp))
    }
}
