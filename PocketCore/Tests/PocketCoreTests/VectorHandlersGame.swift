import Foundation
@testable import PocketCore

/// A game state as vector output: encoded the way the app saves it, with every set sorted.
func normalizedGame(_ value: GameState) throws -> Any {
    guard var game = try VectorIO.encode(value) as? [String: Any] else { throw AppDataError("game is not an object") }
    for key in ["celebratedAchievements", "rewardKeys"] { if let list = game[key] as? [String] { game[key] = list.sorted() } }
    if let months = game["dcaMonths"] as? [[String: Any]] {
        game["dcaMonths"] = months.sorted { (($0["year"] as? Int ?? 0) * 100 + ($0["month"] as? Int ?? 0)) < (($1["year"] as? Int ?? 0) * 100 + ($1["month"] as? Int ?? 0)) }
    }
    if let done = game["questsDone"] as? [String: [String]] { game["questsDone"] = done.mapValues { $0.sorted() } }
    return game
}

func gameInput(_ input: Any, _ key: String = "state") throws -> GameState { try VectorIO.decode(GameState.self, try value(input, key)) }
func portfolioInput(_ input: Any, _ key: String = "portfolio") throws -> Portfolio { try VectorIO.decode(Portfolio.self, try value(input, key)) }
func events(_ list: [XPEvent]) -> [String] { list.map(\.rawValue) }

func snapshotInput(_ input: Any, _ key: String) throws -> LobbySnapshot? {
    try VectorIO.object(input)[key].map { try VectorIO.decode(LobbySnapshot.self, $0) }
}

func lobbyOutput(_ s: LobbySnapshot) -> [String: Any] { ["xp": s.xp, "coins": s.coins, "month": s.month, "quests": s.quests.sorted()] }

func replayOutput(_ r: LobbyReplay?) -> Any {
    guard let r else { return NSNull() }
    return ["newQuests": r.newQuests, "coinsFrom": r.coinsFrom, "coinsTo": r.coinsTo, "xpFrom": r.xpFrom, "xpTo": r.xpTo,
            "levelFrom": r.levelFrom, "levelTo": r.levelTo, "crossesLevel": r.crossesLevel]
}

func dexFacts(_ input: Any) throws -> DexFacts {
    let object = try VectorIO.object(try value(input, "facts"))
    func numbers(_ key: String) throws -> [String: Double] { try object[key].map { try VectorIO.decode([String: Double].self, $0) } ?? [:] }
    let listed = try object["listed"].map { try VectorIO.decode([String: String].self, $0) } ?? [:]
    return DexFacts(feeRate: try numbers("feeRate"), aum: try numbers("aum"), yield: try numbers("yield"), volatility: try numbers("volatility"),
                    listed: try listed.mapValues { try VectorIO.date($0) })
}

/// Runs one scripted step on `game` and returns what the step gave back.
func runStep(_ step: Any, _ game: inout GameState) throws -> Any {
    let action = try string(step, "do")
    switch action {
    case "recordDCA":
        let now = try (VectorIO.object(step)["now"] as? String).map { try VectorIO.date($0) }
        return events(game.recordDCA(on: try at(step, "on"), now: now))
    case "logBuy": return events(game.logBuy(on: try at(step, "on"), now: try at(step, "now")))
    case "visitFund":
        let visit = game.visitFund(try string(step, "symbol"), now: try at(step, "now"))
        return ["new": visit.new, "cardXP": visit.cardXP]
    case "collect": return events(game.collect(try string(step, "symbol"), now: try at(step, "now")))
    case "logDividend":
        let held = (try VectorIO.object(step)["held"] as? Bool) ?? false
        return events(game.logDividend(symbol: try string(step, "symbol"), paid: try at(step, "paid"), held: held, now: try at(step, "now")))
    case "reconcile": return events(game.reconcile(now: try at(step, "now")))
    case "compareFees": return game.compareFees(now: try at(step, "now"))
    case "complete":
        guard let trigger = QuestTrigger(rawValue: try string(step, "trigger")) else { throw AppDataError("unknown trigger") }
        return events(game.complete(trigger, now: try at(step, "now")))
    case "refreshAchievements": return game.refreshAchievements(try portfolioInput(step), now: try at(step, "now"))
    case "migrate": game.migrate(try portfolioInput(step), now: try at(step, "now")); return NSNull()
    case "backfillDCA": game.backfillDCA(from: try portfolioInput(step)); return NSNull()
    case "award":
        guard let event = XPEvent(rawValue: try string(step, "event")) else { throw AppDataError("unknown event") }
        game.award(event, at: try at(step, "at")); return NSNull()
    case "celebrate": game.celebrate(try int(step, "level")); return NSNull()
    case "streak": return game.streak(now: try at(step, "now"))
    case "levelUpDue": return orNull(game.levelUpDue)
    case "coinsSinceCelebration": return game.coinsSinceCelebration
    case "achievementsSinceCelebration": return game.achievementsSinceCelebration
    case "lobby": return lobbyOutput(LobbySnapshot.of(game, now: try at(step, "now")))
    default: throw AppDataError("unknown step \(action)")
    }
}

let gameHandlers: [String: VectorHandler] = [
    "GameRules.xpToReach": { input in GameRules.xpToReach(level: try int(input, "level")) },
    "GameRules.level": { input in GameRules.level(xp: try int(input, "xp")) },
    "GameRules.progress": { input in
        let p = GameRules.progress(xp: try int(input, "xp"))
        return ["into": p.into, "needed": p.needed]
    },
    "GameState.streak": { input in try gameInput(input).streak(now: try at(input, "now")) },
    "Quests.forMonth": { input in
        guard let habit = Habit(rawValue: try string(input, "habit")) else { throw AppDataError("unknown habit") }
        let newbie = (try VectorIO.object(input)["isNewbie"] as? Bool) ?? false
        return Quests.forMonth(try VectorIO.decode(YearMonth.self, try value(input, "month")), habit: habit, isNewbie: newbie).map(\.id)
    },
    "Achievements.longestDividendRun": { input in Achievements.longestDividendRun(try portfolioInput(input)) },
    "Achievements.hasAnniversary": { input in Achievements.hasAnniversary(try portfolioInput(input), now: try at(input, "now")) },
    "Achievements.steady": { input in Achievements.steady(try portfolioInput(input), now: try at(input, "now")) },
    "Achievements.progressAll": { input in
        let game = try gameInput(input), p = try portfolioInput(input), now = try at(input, "now")
        return Dictionary(uniqueKeysWithValues: Achievements.all.map { ($0.id, $0.progress(game, p, now)) })
    },
    "Achievements.shown": { input in
        Achievements.shown(upcoming: (try VectorIO.object(input)["upcoming"] as? Bool) ?? false)
            .map { ["id": $0.id, "title": $0.title, "goal": $0.goal, "comingSoon": $0.comingSoon] as [String: Any] }
    },
    "DexSeries.of": { input in DexSeries.of(try VectorIO.decode(Fund.self, try value(input, "fund"))).rawValue },
    "Dex.stats": { input in
        let s = Dex.stats(for: try VectorIO.decode(Fund.self, try value(input, "fund")), among: try VectorIO.decode([Fund].self, try value(input, "among")),
                          facts: try dexFacts(input))
        return ["fee": s.fee, "size": s.size, "yield": s.yield, "volatility": s.volatility, "history": s.history]
    },
    "LobbyReplay.between": { input in
        guard let now = try snapshotInput(input, "now") else { throw AppDataError("no now") }
        let order = try VectorIO.decode([String].self, try value(input, "questOrder"))
        return replayOutput(LobbyReplay.between(shown: try snapshotInput(input, "shown"), now: now, questOrder: order))
    },
    "LobbyReplay.arrival": { input in
        guard let now = try snapshotInput(input, "now") else { throw AppDataError("no now") }
        let order = try VectorIO.decode([String].self, try value(input, "questOrder"))
        let due = (try VectorIO.object(input)["levelUpDue"] as? NSNumber)?.intValue
        return replayOutput(LobbyReplay.arrival(shown: try snapshotInput(input, "shown"), now: now, questOrder: order, levelUpDue: due,
                                                celebratedLevel: try int(input, "celebratedLevel")))
    },
    "LobbySnapshot.of": { input in lobbyOutput(LobbySnapshot.of(try gameInput(input), now: try at(input, "now"))) },
    "GameState.script": { input in
        var game = try gameInput(input)
        guard let steps = try VectorIO.object(input)["steps"] as? [Any] else { throw AppDataError("no steps") }
        var results: [Any] = []
        for step in steps { results.append(try runStep(step, &game)) }
        return ["steps": results, "state": try normalizedGame(game)]
    },
]
