import Foundation

/// Launch arguments that set up game progress for UI tests and screenshots; ignored without `--ui-testing`.
///
/// - `--demo-streak <n>`: DCA recorded in each of the n months up to and including this one.
/// - `--demo-level <n>`: experience at the start of level n, `(n - 1) × GameRules.xpPerLevel`.
/// - `--demo-xp <n>`: experience n (wins over `--demo-level`).
///
/// Read elsewhere: `--skin <id>` (SkinStore), `--open <feature>` (the root view), `--offline` and `--reduce-motion`.
enum DemoArguments {
    static func apply(to game: inout GameState, args: [String], now: Date) {
        guard args.contains("--ui-testing") else { return }
        func number(_ flag: String) -> Int? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1), let n = Int(args[i + 1]), n >= 0 else { return nil }
            return n
        }
        if let streak = number("--demo-streak") {
            var months = Set<YearMonth>(), month = YearMonth(now)
            for _ in 0..<streak { months.insert(month); month = month.previous() }
            game.dcaMonths = months
            game.longestStreak = max(game.longestStreak, streak)
        }
        if let level = number("--demo-level"), level >= 1 { game.xp = (level - 1) * GameRules.xpPerLevel }
        if let xp = number("--demo-xp") { game.xp = xp }
    }
}
