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

enum Opening {
    /// The whole timeline, the hold included; at this point the first launch shows 輕點開始 and later launches leave.
    static let length = 3.0
    /// Reduce Motion: everything fades in over `reducedFade`, and later launches go on after `reducedLength`.
    static let reducedFade = 0.8
    static let reducedLength = 1.2
    /// When each step begins (the table in the design).
    static let marks: [(at: Double, step: OpeningStep)] = [(0, .ring), (0.4, .dollar), (0.9, .rays), (1.4, .title), (2.0, .line), (3.0, .done)]

    /// The step under way at `time` seconds after the start. Under Reduce Motion there is no movement: the final state.
    static func step(at time: Double, reduceMotion: Bool) -> OpeningStep {
        if reduceMotion { return .done }
        return marks.last(where: { time >= $0.at })?.step ?? .ring
    }

    /// Whether and how the opening plays. `firstLaunch`: the first-launch flow opens on the splash (also when
    /// `--open splash` forces it). Under `--ui-testing` later launches skip it, so every existing UI test and screenshot
    /// is unchanged, and the first launch shows its final frame; `--opening` forces the animation even then. A launch
    /// that came from tapping a notification skips it.
    static func play(firstLaunch: Bool, arguments: [String], fromNotification: Bool) -> OpeningPlay {
        let testing = arguments.contains("--ui-testing")
        if testing && arguments.contains("--opening") { return .animated }
        if testing || fromNotification { return firstLaunch ? .still : .off }
        return .animated
    }

    /// `--ui-testing --opening`: a later launch's opening waits on its final frame for 略過 instead of going on by
    /// itself, so a UI test always finds 略過, however slowly the simulator launches.
    static func holds(_ arguments: [String]) -> Bool { arguments.contains("--ui-testing") && arguments.contains("--opening") }

    /// The share of the 「$」's 0.6 s spent falling; the rest is the landing squash.
    static let fallShare = 0.6
    /// How far above its place the 「$」 starts, in points.
    static let dropHeight: Double = 320
    /// The landing squash at its widest (a fraction of the size).
    static let squash = 0.12

    /// When the 「$」 lands (the light haptic): 0.76 s, or the next whole step for the stepped (pixel) skin.
    static func landing(_ motion: SkinMotion) -> Double {
        let time = marks[1].at + 0.6 * fallShare
        return motion.stepped ? (time * motion.stepsPerSecond).rounded(.up) / motion.stepsPerSecond : time
    }

    /// A spring from 0 to 1 over `u` in 0…1 that has settled by 1: the overshoot grows with the skin's bounce
    /// (`SkinMotion.bounce`: none for pixel, the most for stitch).
    static func settle(_ u: Double, bounce: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        let decay = 7 - 3 * bounce, frequency = Double.pi * (1.5 + 2 * bounce)
        return 1 - exp(-decay * u) * cos(frequency * u) * (1 - u)
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
        func fade(_ u: Double, _ share: Double) -> Double { min(u / share, 1) }
        let bounce = motion.bounce
        var pose = OpeningPose()
        // 0.0–0.6: the stage ring springs open from 0.6.
        let ring = part(0, 0.6)
        pose.ringScale = 1 - 0.4 * (1 - Opening.settle(ring, bounce: bounce))
        pose.ringOpacity = fade(ring, 0.25)
        // 0.4–1.0: the 「$」 falls (gathering speed), then squashes as it lands.
        let drop = part(0.4, 0.6), fall = min(drop / Opening.fallShare, 1)
        pose.dollarDrop = 1 - fall * fall
        pose.dollarOpacity = fade(drop, 0.15)
        if drop > Opening.fallShare {
            let v = (drop - Opening.fallShare) / (1 - Opening.fallShare)
            pose.dollarSquash = Opening.squash * sin(.pi * (1 + bounce) * v) * (1 - v)
        }
        // 0.9–1.6: the rays sweep out from the centre, turning and growing from 0.
        let rays = part(0.9, 0.7), spread = Opening.settle(rays, bounce: bounce)
        pose.raysScale = spread
        pose.raysTurn = -45 * (1 - spread)
        pose.raysOpacity = fade(rays, 0.3)
        pose.raysSweep = motion.particle == .stroke ? 1 - (1 - rays) * (1 - rays) : 1
        // 1.4–2.2: 「ETF 袋著走」 rises and fades in; the tag pops a little after it.
        let title = part(1.4, 0.6)
        pose.titleRise = Opening.settle(title, bounce: bounce)
        pose.titleOpacity = fade(title, 0.6)
        let tag = part(1.7, 0.5)
        pose.tagScale = 1 - 0.7 * (1 - Opening.settle(tag, bounce: bounce))
        pose.tagOpacity = fade(tag, 0.3)
        // 2.0–2.6: the line fades in. Then the hold.
        let line = part(2.0, 0.6)
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
}
