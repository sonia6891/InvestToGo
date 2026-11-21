import Foundation

// 開場動畫 (docs/superpowers/specs/2026-11-21-opening-animation-design.md): about three seconds on every cold launch,
// skippable with 略過 or a tap anywhere. The first launch then holds on 「→ 輕點開始 ←」; later launches go on to the
// lobby by themselves.

/// How the opening plays at this launch.
enum OpeningPlay: Equatable {
    /// No opening: a later launch goes straight to the lobby.
    case off
    /// The final frame at once (the first launch under `--ui-testing`, `--open splash`, or a launch from a notification).
    case still
    /// The animated opening.
    case animated
}

/// Where the opening is on its timeline: the step that began last.
enum OpeningStep: Int, Comparable {
    case ring, dollar, rays, title, line, done
    static func < (a: OpeningStep, b: OpeningStep) -> Bool { a.rawValue < b.rawValue }
}

/// When a step begins and how long it moves, in seconds.
struct OpeningWindow: Equatable {
    var start: Double
    var length: Double
    var end: Double { start + length }
}

enum Opening {
    /// The timeline (the table in the design): each step's start and length, in order. The one source of timing: the
    /// poses (`OpeningPose.at`), the landing haptic (`landing`) and `step(at:)` all read it. 2.6–3.0 s is the hold;
    /// `.done` at 3.0 s is when the first launch shows 輕點開始 and later launches leave.
    static let timeline: [(step: OpeningStep, window: OpeningWindow)] = [
        (.ring, OpeningWindow(start: 0, length: 0.6)),
        (.dollar, OpeningWindow(start: 0.4, length: 0.6)),
        (.rays, OpeningWindow(start: 0.9, length: 0.7)),
        (.title, OpeningWindow(start: 1.4, length: 0.8)),
        (.line, OpeningWindow(start: 2.0, length: 0.6)),
        (.done, OpeningWindow(start: 3.0, length: 0)),
    ]
    static func window(_ step: OpeningStep) -> OpeningWindow {
        timeline.first(where: { $0.step == step })?.window ?? OpeningWindow(start: 3.0, length: 0)
    }
    /// The whole timeline, the hold included.
    static var length: Double { window(.done).start }
    /// Reduce Motion: everything fades in over `reducedFade`, and later launches go on after `reducedLength`.
    static let reducedFade = 0.8
    static let reducedLength = 1.2

    /// The step under way at `time` seconds after the start: the one that began last. Under Reduce Motion there is no
    /// movement: the final state.
    static func step(at time: Double, reduceMotion: Bool) -> OpeningStep {
        if reduceMotion { return .done }
        return timeline.last(where: { time >= $0.window.start })?.step ?? .ring
    }

    /// Whether and how the opening plays. `firstLaunch`: the first-launch flow opens on the splash (also when
    /// `--open splash` forces it). Under `--ui-testing` later launches skip it, so every existing UI test and screenshot
    /// is unchanged, and the first launch shows its final frame; `--opening` forces the animation even then. A launch
    /// that came from tapping a notification skips it, and so does a scene iOS builds again while the process lives
    /// (`alreadyPlayed`): the opening plays once per cold launch.
    static func play(firstLaunch: Bool, arguments: [String], fromNotification: Bool, alreadyPlayed: Bool = false) -> OpeningPlay {
        if alreadyPlayed { return firstLaunch ? .still : .off }
        let testing = arguments.contains("--ui-testing")
        if testing && arguments.contains("--opening") { return .animated }
        if testing || fromNotification { return firstLaunch ? .still : .off }
        return .animated
    }

    /// `--ui-testing --opening`: a later launch's opening waits on its final frame for 略過 instead of going on by
    /// itself, so a UI test always finds 略過, however slowly the simulator launches.
    static func holds(_ arguments: [String]) -> Bool { arguments.contains("--ui-testing") && arguments.contains("--opening") }

    /// The share of the 「$」's step spent falling; the rest is the landing squash.
    static let fallShare = 0.6
    /// How far above its place the 「$」 starts, in points.
    static let dropHeight: Double = 320
    /// The landing squash at its widest (a fraction of the size).
    static let squash = 0.12

    /// When the 「$」 lands (the light haptic): 0.76 s, or the next whole step for the stepped (pixel) skin.
    static func landing(_ motion: SkinMotion) -> Double {
        let drop = window(.dollar)
        let time = drop.start + drop.length * fallShare
        return motion.stepped ? (time * motion.stepsPerSecond).rounded(.up) / motion.stepsPerSecond : time
    }

    /// A spring from 0 to 1 over `u` in 0…1 that has settled by 1: the overshoot grows with the skin's bounce
    /// (`SkinMotion.bounce`: none for pixel, the most for stitch). With no bounce it never passes 1.
    static func settle(_ u: Double, bounce: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        let decay = 7 - 3 * bounce, frequency = Double.pi * (1.5 + 2 * bounce)
        let value = 1 - exp(-decay * u) * cos(frequency * u) * (1 - u)
        return bounce > 0 ? value : min(value, 1)
    }
}

/// Every moving part of the opening at one moment. `final` is the frame it ends on (and the still splash).
struct OpeningPose: Equatable {
    var ringScale = 1.0, ringOpacity = 1.0
    /// 1: `Opening.dropHeight` above its place; 0: landed.
    var dollarDrop = 0.0
    /// Above 0 squashed wide, below 0 stretched tall.
    var dollarSquash = 0.0
    var dollarOpacity = 1.0
    var raysScale = 1.0, raysTurn = 0.0, raysOpacity = 1.0
    /// Sketch draws its rays on like strokes: the share of the turn revealed so far. 1 for the other skins.
    var raysSweep = 1.0
    /// 0: below its place and clear; 1: in place.
    var titleRise = 1.0, titleOpacity = 1.0
    var tagScale = 1.0, tagOpacity = 1.0
    var lineOpacity = 1.0

    static let final = OpeningPose()

    /// The pose `time` seconds after the start, in the skin's character: its spring (`settle`), and for sketch the
    /// rays drawn on. The stepped (pixel) skin passes a stepped time (`SkinMotion.clock`).
    static func at(_ time: Double, motion: SkinMotion) -> OpeningPose {
        if time >= Opening.length { return .final }
        func part(_ start: Double, _ length: Double) -> Double { min(max((time - start) / length, 0), 1) }
        func moving(_ step: OpeningStep) -> Double { let w = Opening.window(step); return part(w.start, w.length) }
        func fade(_ u: Double, _ share: Double) -> Double { min(u / share, 1) }
        let bounce = motion.bounce
        var pose = OpeningPose()
        // .ring (0.0–0.6): the stage ring springs open from 0.6.
        let ring = moving(.ring)
        pose.ringScale = 1 - 0.4 * (1 - Opening.settle(ring, bounce: bounce))
        pose.ringOpacity = fade(ring, 0.25)
        // .dollar (0.4–1.0): the 「$」 falls (gathering speed), then squashes as it lands.
        let drop = moving(.dollar), fall = min(drop / Opening.fallShare, 1)
        pose.dollarDrop = 1 - fall * fall
        pose.dollarOpacity = fade(drop, 0.15)
        if drop > Opening.fallShare {
            let v = (drop - Opening.fallShare) / (1 - Opening.fallShare)
            pose.dollarSquash = Opening.squash * sin(.pi * (1 + bounce) * v) * (1 - v)
        }
        // .rays (0.9–1.6): the rays sweep out from the centre, turning and growing from 0.
        let rays = moving(.rays), spread = Opening.settle(rays, bounce: bounce)
        pose.raysScale = spread
        pose.raysTurn = -45 * (1 - spread)
        pose.raysOpacity = fade(rays, 0.3)
        pose.raysSweep = motion.particle == .stroke ? 1 - (1 - rays) * (1 - rays) : 1
        // .title (1.4–2.2): 「ETF 袋著走」 rises and fades in over its first 0.6 s; the tag pops over its last 0.5 s.
        let titleWindow = Opening.window(.title)
        let title = part(titleWindow.start, titleWindow.length - 0.2)
        pose.titleRise = Opening.settle(title, bounce: bounce)
        pose.titleOpacity = fade(title, 0.6)
        let tag = part(titleWindow.end - 0.5, 0.5)
        pose.tagScale = 1 - 0.7 * (1 - Opening.settle(tag, bounce: bounce))
        pose.tagOpacity = fade(tag, 0.3)
        // .line (2.0–2.6): the line fades in. Then the hold until .done.
        let line = moving(.line)
        pose.lineOpacity = line * line * (3 - 2 * line)
        return pose
    }
}

/// Whether this launch came from tapping a notification. Set by the notification delegate (`didReceive`), which iOS
/// calls during a cold launch from a tap, sometimes after the first frame: the opening watches it and steps aside
/// (the first launch to its final frame, later launches to the lobby).
@MainActor final class OpeningLaunch: ObservableObject {
    static let shared = OpeningLaunch()
    @Published private(set) var fromNotification = false
    func notificationOpened() { fromNotification = true }
    /// The opening has begun in this process: a scene iOS builds again while the process lives does not replay it.
    private(set) var played = false
    func markPlayed() { played = true }
}
