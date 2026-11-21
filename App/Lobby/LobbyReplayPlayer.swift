import SwiftUI

// The lobby's replay (spec 5.3, 5.4): experience, coins and quest ticks are mostly earned on other screens, so the
// lobby remembers what it last showed and, when it comes back on screen, plays what grew since: the new quests tick,
// coins fly from the object just left to the coin counter, 「+N XP」 floats up, and the experience bar moves. When the
// bar fills, it flashes and LEVEL×UP follows (one big event at a time). A tap anywhere jumps to the final numbers.
// Everything here is decoration: never driven by prices, hidden from VoiceOver (which reads the final numbers), and
// never hit-testable.

/// What the lobby last showed, kept on this phone only (never in a backup, spec 5.3): saved each time the lobby
/// appears, cleared by a restore so the restored numbers show without a replay.
struct LobbyShownStore {
    static let key = "lobby.shownSnapshot"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> LobbySnapshot? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(LobbySnapshot.self, from: $0) }
    }

    func save(_ s: LobbySnapshot) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func reset() { defaults.removeObject(forKey: Self.key) }

    /// `--reset` with `--ui-testing`: the UI tests' records start empty, and so does what the lobby showed.
    static func reset(_ args: [String]) {
        guard args.contains("--ui-testing"), args.contains("--reset") else { return }
        LobbyShownStore().reset()
    }
}

/// When each part of a replay plays, in seconds from its start. Quest ticks first, then the coins, then 「+N XP」
/// with the bar, and the flash when the bar fills: at most two seconds after `lead`.
struct LobbyReplayPlan: Equatable {
    struct Tick: Equatable {
        var quest: String
        var at: Double
    }

    var lead: Double
    var ticks: [Tick]
    /// Between two ticks.
    var tickGap: Double
    /// When the coins take off; nil when no coins were earned.
    var coinsAt: Double?
    /// When the bar starts moving (and 「+N XP」 floats); nil when the experience did not grow and no level is due.
    var barAt: Double?
    /// The bar fills, flashes and hands over to LEVEL×UP.
    var fillsToLevelUp: Bool
    /// When the replay is over (LEVEL×UP, if any, starts here).
    var total: Double

    static let ticksAtMost = 0.6, tickGapAtMost = 0.22
    static let flight = 0.5, coinSettle = 0.12
    static let bar = 0.45, flash = 0.3
    /// How long 「+N XP」 floats; it starts with the bar.
    static let float = 0.75

    static func of(_ replay: LobbyReplay, lead: Double = 0) -> LobbyReplayPlan {
        var t = lead
        let n = replay.newQuests.count
        let gap = n > 0 ? min(tickGapAtMost, ticksAtMost / Double(n)) : 0
        let ticks = replay.newQuests.enumerated().map { Tick(quest: $0.element, at: t + Double($0.offset) * gap) }
        t += Double(n) * gap
        var coinsAt: Double?
        if replay.coinsTo > replay.coinsFrom { coinsAt = t; t += flight + coinSettle }
        var barAt: Double?
        if replay.xpTo > replay.xpFrom || replay.crossesLevel {
            barAt = t
            t += replay.crossesLevel ? bar + flash : max(bar, replay.xpTo > replay.xpFrom ? float : 0)
        }
        return LobbyReplayPlan(lead: lead, ticks: ticks, tickGap: gap, coinsAt: coinsAt, barAt: barAt,
                               fillsToLevelUp: replay.crossesLevel, total: t)
    }
}

/// The numbers the lobby draws while a replay plays, in place of the saved ones.
struct LobbyDisplay: Equatable {
    var level: Int
    /// How full the experience bar is (0...1).
    var fraction: Double
    var coins: Int
    /// Quests already done that have not ticked on screen yet.
    var unticked: Set<String>
}

/// 「+N XP」 floating up beside the bar since `start`.
struct XPFloat: Equatable {
    var amount: Int
    var start: Date
}

/// Plays a `LobbyReplay` on the lobby: publishes what to draw, step by step, and calls `celebrate` once the bar has
/// filled. `cancel()` jumps to the final state (the saved numbers) without LEVEL×UP, which waits for the next time the
/// lobby is seen (spec 5.4).
@MainActor final class LobbyReplayPlayer: ObservableObject {
    @Published private(set) var display: LobbyDisplay?
    /// The coins have been flying since then.
    @Published private(set) var flight: Date?
    @Published private(set) var xpFloat: XPFloat?
    /// The quest whose tick is popping.
    @Published private(set) var popping: String?
    /// Plays each quest's confetti once per change.
    @Published private(set) var confetti: [String: Int] = [:]
    /// The full bar's flash.
    @Published private(set) var flashing = false
    /// From the start until the final numbers show (a tap during it cancels).
    @Published private(set) var playing = false

    private var task: Task<Void, Never>?
    /// The bar filled and LEVEL×UP was asked for; when it closes, the bar grows from the new level's start.
    private var awaitingCover = false
    private var coverShown = false
    private var grown: (level: Int, fraction: Double)?

    /// How full the bar is at `xp`, within its level.
    static func fraction(xp: Int) -> Double {
        let p = GameRules.progress(xp: xp)
        return Double(p.into) / Double(max(p.needed, 1))
    }

    func play(_ replay: LobbyReplay, lead: Double, skin: Skin, celebrate: @escaping () -> Void) {
        cancel()
        let plan = LobbyReplayPlan.of(replay, lead: lead)
        let motion = SkinMotion.of(skin)
        let sound = SkinStore.shared.soundOn
        grown = (replay.levelTo, Self.fraction(xp: replay.xpTo))
        display = LobbyDisplay(level: replay.crossesLevel ? replay.levelFrom : replay.levelTo, fraction: Self.fraction(xp: replay.xpFrom),
                               coins: replay.coinsFrom, unticked: Set(replay.newQuests))
        playing = true
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(replay, plan: plan, motion: motion, sound: sound, celebrate: celebrate)
        }
    }

    /// The final state at once: the saved numbers, nothing flying. No LEVEL×UP.
    func cancel() {
        task?.cancel(); task = nil
        awaitingCover = false; coverShown = false
        guard playing || display != nil || flight != nil || xpFloat != nil else { return }
        finish()
    }

    /// LEVEL×UP came up over the lobby.
    func coverOpened() { if awaitingCover { coverShown = true } }

    /// LEVEL×UP was closed: the bar grows from the new level's start to where it is now.
    func coverClosed() {
        guard awaitingCover, coverShown else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await self.grow()
        }
    }

    private func run(_ replay: LobbyReplay, plan: LobbyReplayPlan, motion: SkinMotion, sound: Bool, celebrate: @escaping () -> Void) async {
        guard await pause(plan.lead) else { return }
        // 0. New quests tick, one after another.
        for tick in plan.ticks {
            withAnimation(motion.spring) { popping = tick.quest }
            change(motion.spring) { $0.unticked.remove(tick.quest) }
            confetti[tick.quest, default: 0] += 1
            SoundFX.tick(enabled: sound)
            Haptics.tick()
            guard await pause(plan.tickGap) else { return }
        }
        withAnimation(motion.spring) { popping = nil }
        // 1. Coins fly to the counter, which counts up as they land.
        if plan.coinsAt != nil {
            flight = Date()
            guard await pause(LobbyReplayPlan.flight / 2) else { return }
            let gain = replay.coinsTo - replay.coinsFrom, steps = max(1, min(6, gain))
            for step in 1...steps {
                change(.snappy(duration: 0.08)) { $0.coins = replay.coinsFrom + gain * step / steps }
                SoundFX.tick(enabled: sound)
                guard await pause(LobbyReplayPlan.flight / 2 / Double(steps)) else { return }
            }
            SoundFX.coin(enabled: sound)
            guard await pause(LobbyReplayPlan.coinSettle) else { return }
            flight = nil
        }
        // 2–3. 「+N XP」 floats while the bar moves; 4. full: a flash, then LEVEL×UP.
        if plan.barAt != nil {
            if replay.xpTo > replay.xpFrom { xpFloat = XPFloat(amount: replay.xpTo - replay.xpFrom, start: Date()) }
            let target = plan.fillsToLevelUp ? 1 : Self.fraction(xp: replay.xpTo)
            change(motion.stepped ? .linear(duration: LobbyReplayPlan.bar) : .easeOut(duration: LobbyReplayPlan.bar)) { $0.fraction = target }
            guard await pause(LobbyReplayPlan.bar) else { return }
            if plan.fillsToLevelUp {
                withAnimation(.easeOut(duration: 0.12)) { flashing = true }
                Haptics.tick()
                guard await pause(LobbyReplayPlan.flash / 2) else { return }
                withAnimation(.easeIn(duration: 0.15)) { flashing = false }
                guard await pause(LobbyReplayPlan.flash / 2) else { return }
                awaitingCover = true; coverShown = false
                celebrate()
                // No LEVEL×UP came (none was due, or the lobby was left): the bar grows on its own.
                guard await pause(1.0), !coverShown else { return }
                await grow()
                return
            }
            guard await pause(max(0, LobbyReplayPlan.float - LobbyReplayPlan.bar)) else { return }
        }
        finish()
    }

    /// After a level-up: the badge shows the new level and the bar grows from its start.
    private func grow() async {
        awaitingCover = false; coverShown = false
        guard let grown, display != nil else { finish(); return }
        change(nil) { $0.level = grown.level; $0.fraction = 0 }
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) { xpFloat = nil; flashing = false }
        // On the next turn, so the growth is a fresh animated change.
        guard await pause(0.02) else { return }
        change(.easeOut(duration: LobbyReplayPlan.bar)) { $0.fraction = grown.fraction }
        guard await pause(LobbyReplayPlan.bar) else { return }
        finish()
    }

    /// Changes what is drawn, with `animation` (nil: at once, without one).
    private func change(_ animation: Animation?, _ edit: (inout LobbyDisplay) -> Void) {
        guard var next = display else { return }
        edit(&next)
        if let animation {
            withAnimation(animation) { display = next }
        } else {
            var still = Transaction(); still.disablesAnimations = true
            withTransaction(still) { display = next }
        }
    }

    private func finish() {
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) {
            display = nil; flight = nil; xpFloat = nil; popping = nil; flashing = false; playing = false
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        if seconds > 0 { try? await Task.sleep(for: .milliseconds(Int((seconds * 1000).rounded()))) }
        return !Task.isCancelled
    }
}

/// The coins of a replay flying in an arc from `from` to `to` (0.5 s each, a little apart). The pixel skin steps them.
struct ReplayCoinFlight: View {
    let start: Date
    let from: CGPoint
    let to: CGPoint
    var count = 5
    @Environment(\.skin) private var skin
    static let spacing = 0.05

    var body: some View {
        let motion = SkinMotion.of(skin)
        let fill = skin.color(\.accent), rim = skin.color(\.ink).opacity(0.35)
        let each = LobbyReplayPlan.flight - Self.spacing * Double(count - 1)
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let t = motion.clock(timeline.date.timeIntervalSince(start))
                for i in 0..<count {
                    let p = (t - Double(i) * Self.spacing) / each
                    guard p >= 0, p <= 1 else { continue }
                    let e = CGFloat(p * p * (3 - 2 * p))
                    let x = from.x + (to.x - from.x) * e + CGFloat(i - count / 2) * 6 * sin(.pi * e)
                    let y = from.y + (to.y - from.y) * e - 70 * 4 * e * (1 - e)
                    let r = 7 - 2 * e
                    let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                    let shape = motion.stepped ? Path(rect) : Path(ellipseIn: rect)
                    context.fill(shape, with: .color(fill))
                    context.stroke(shape, with: .color(rim), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 「+N XP」 rising about 22pt above `at` and fading.
struct ReplayXPFloat: View {
    let float: XPFloat
    let at: CGPoint
    @Environment(\.skin) private var skin

    var body: some View {
        let motion = SkinMotion.of(skin)
        TimelineView(.animation) { timeline in
            let p = min(max(motion.clock(timeline.date.timeIntervalSince(float.start)) / LobbyReplayPlan.float, 0), 1)
            Text("+\(float.amount) XP")
                .skinFont(.mono(12))
                .foregroundStyle(skin.color(skin.lightText ? \.accent : \.ink))
                .fixedSize()
                .scaleEffect(CGFloat(0.8 + 0.2 * min(p / 0.2, 1)))
                .opacity(min(p / 0.15, 1) * (p > 0.7 ? (1 - p) / 0.3 : 1))
                .position(x: at.x, y: at.y - 22 * CGFloat(p))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
