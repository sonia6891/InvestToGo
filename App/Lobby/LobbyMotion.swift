import SwiftUI
import UIKit

// The living lobby (spec 5.1): each lobby object's signature move, the numeral's shine, the experience bar's
// highlight and the quest reward's breathing. All of it is decoration drawn over or applied to the existing pictures
// (no new art), driven only by the clock and never by prices, hidden from VoiceOver and never hit-testable. It runs
// only while the lobby's `ambient` gate is open (`AmbientMotion.allowed`), so `--ui-testing`, Reduce Motion and Low
// Power Mode see the lobby at rest.

/// A lobby object's signature move, every 4–7 s: 找 ETF swings, 配息's top coin flips, 口袋 squashes and a coin hops
/// out of it, 工具 lights a key.
enum LobbySignature: Equatable {
    case swing, flip, hop, blink

    static func of(_ feature: Feature) -> LobbySignature {
        switch feature {
        case .find: return .swing
        case .dividends: return .flip
        case .pocket: return .hop
        // 成就 sits in the top bar and has no move of its own; it shares the tools' light so the switch is complete.
        case .tools, .achievements: return .blink
        }
    }

    /// Where in its cycles an object starts (0...1), so the four never move together.
    static func phase(_ feature: Feature) -> Double {
        switch feature {
        case .find: return 0
        case .dividends: return 0.25
        case .pocket: return 0.5
        case .tools: return 0.75
        case .achievements: return 0
        }
    }

    /// Seconds between two moves of the object with this phase: 4 s at phase 0 up to 6.25 s at phase 0.75.
    static func interval(phase: Double) -> Double { 4 + 3 * min(max(phase, 0), 1) }
    /// How long one move lasts.
    static let moveDuration = 0.9

    /// How far through its move the object is at `time` (0..<1), or nil between moves. Deterministic: the same time
    /// always gives the same pose.
    static func progress(time: Double, phase: Double) -> Double? {
        let period = interval(phase: phase)
        var local = (time + phase * period).truncatingRemainder(dividingBy: period)
        if local < 0 { local += period }
        return local < moveDuration ? local / moveDuration : nil
    }

    /// The whole picture's transform at `progress` (nil: at rest).
    struct Pose: Equatable {
        var rotation: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var dy: CGFloat = 0
    }

    func pose(_ progress: Double?) -> Pose {
        guard let p = progress else { return Pose() }
        switch self {
        case .swing:
            // Two swings of ±8°, easing out over the second half.
            return Pose(rotation: 8 * sin(4 * .pi * p) * min(1, 2 * (1 - p)))
        case .flip:
            // The stack hops a little while its top coin turns.
            return Pose(dy: -6 * CGFloat(sin(.pi * p)))
        case .hop:
            // A squash in the first quarter, as if it breathed the coin out.
            let s = p < 0.25 ? CGFloat(sin(.pi * p / 0.25)) : 0
            return Pose(scaleX: 1 + 0.08 * s, scaleY: 1 - 0.08 * s)
        case .blink:
            return Pose(rotation: 3 * sin(4 * .pi * p) * (1 - p))
        }
    }
}

extension SkinMotion {
    /// The time the skin's motion shows: whole steps for the stepped (pixel) skin, smooth for the others.
    func clock(_ time: Double) -> Double { stepped ? (time * stepsPerSecond).rounded(.down) / stepsPerSecond : time }
    /// The least time between two redraws of an ambient clock: 1/30 s, or one step of the stepped (pixel) skin.
    var frameInterval: Double { stepped ? 1 / max(stepsPerSecond, 1) : 1.0 / 30 }
}

/// Plays a lobby object's signature move on its picture while `enabled`; still otherwise.
struct SignatureMove: ViewModifier {
    let signature: LobbySignature
    let phase: Double
    let enabled: Bool
    @Environment(\.skin) private var skin

    func body(content: Content) -> some View {
        let motion = SkinMotion.of(skin)
        let period = LobbySignature.interval(phase: phase)
        // Redraws only during the move (0.9 s of every 4–6.25 s); at rest nothing changes, so the clock idles.
        let schedule = MoveSchedule(period: period, offset: -phase * period, duration: LobbySignature.moveDuration, step: motion.frameInterval)
        TimelineView(schedule.paused(!enabled)) { timeline in
            let p = enabled ? LobbySignature.progress(time: motion.clock(timeline.date.timeIntervalSinceReferenceDate), phase: phase) : nil
            let pose = signature.pose(p)
            content
                .overlay { if let p { SignatureMark(signature: signature, progress: p) } }
                .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(pose.rotation))
                .offset(y: pose.dy)
        }
    }
}

/// What a move draws over a 76pt lobby picture: the flipping coin's glint near the top, the coin hopping out of the
/// pocket, the calculator key lighting up.
private struct SignatureMark: View {
    let signature: LobbySignature
    let progress: Double
    @Environment(\.skin) private var skin

    var body: some View {
        let p = progress
        Group {
            switch signature {
            case .swing:
                EmptyView()
            case .flip:
                Ellipse().fill(Color.white)
                    .frame(width: 34, height: 12)
                    .scaleEffect(x: max(0.08, abs(CGFloat(cos(2 * .pi * p)))), y: 1)
                    .opacity(0.85 * sin(.pi * p))
                    .offset(y: -24)
            case .hop:
                // Out of the top, up about 34pt and back in, fading at both ends.
                let q = min(max((p - 0.15) / 0.85, 0), 1)
                let fade = min(q / 0.15, (1 - q) / 0.15, 1)
                ZStack {
                    Circle().fill(skin.color(\.accent))
                    Circle().strokeBorder(skin.color(\.ink).opacity(0.35), lineWidth: 2)
                }
                .frame(width: 14, height: 14)
                .scaleEffect(x: max(0.25, abs(CGFloat(cos(3 * .pi * q)))), y: 1)
                .offset(y: -26 - 34 * CGFloat(4 * q * (1 - q)))
                .opacity(max(0, fade))
            case .blink:
                RoundedRectangle(cornerRadius: skin.style.button == .pixelBlock ? 0 : 2)
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .white, radius: 4)
                    .offset(x: 10, y: 8)
                    .opacity(0.9 * abs(sin(2 * .pi * p)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A diagonal band of light that crosses the numeral now and then (every 7 s, 1.2 s long) while `enabled`.
struct HeroShine: View {
    var enabled: Bool
    /// The band's brightest opacity.
    var peak: Double = 0.55
    @Environment(\.skin) private var skin

    static let interval = 7.0, duration = 1.2
    /// How far across the band is at `time` (0..<1), or nil between shines. Starts 2 s into the cycle, so the first
    /// shine never lands on the opening.
    static func progress(time: Double) -> Double? {
        var local = (time - 2).truncatingRemainder(dividingBy: interval)
        if local < 0 { local += interval }
        return local < duration ? local / duration : nil
    }

    var body: some View {
        let motion = SkinMotion.of(skin)
        let schedule = MoveSchedule(period: Self.interval, offset: 2, duration: Self.duration, step: motion.frameInterval)
        TimelineView(schedule.paused(!enabled)) { timeline in
            Canvas { context, size in
                guard enabled, size.width > 0, let p = Self.progress(time: motion.clock(timeline.date.timeIntervalSinceReferenceDate)) else { return }
                let w = max(size.width * 0.2, 30), slant = size.height * 0.3
                let x = -w - slant + (size.width + 2 * (w + slant)) * p
                var band = Path()
                band.move(to: CGPoint(x: x - w / 2 + slant, y: 0))
                band.addLine(to: CGPoint(x: x + w / 2 + slant, y: 0))
                band.addLine(to: CGPoint(x: x + w / 2 - slant, y: size.height))
                band.addLine(to: CGPoint(x: x - w / 2 - slant, y: size.height))
                band.closeSubpath()
                let light = Gradient(colors: [.white.opacity(0), .white.opacity(peak), .white.opacity(0)])
                context.fill(band, with: .linearGradient(light, startPoint: CGPoint(x: x - w / 2 - slant / 2, y: size.height / 2),
                                                         endPoint: CGPoint(x: x + w / 2 + slant / 2, y: size.height / 2)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A short highlight that runs along the experience bar's fill: across in 1.6 s, every 3.2 s, while `enabled`.
struct BarShine: View {
    var enabled: Bool
    var color: Color
    @Environment(\.skin) private var skin

    var body: some View {
        let motion = SkinMotion.of(skin)
        let schedule = MoveSchedule(period: 3.2, offset: 0, duration: 1.6, step: motion.frameInterval)
        TimelineView(schedule.paused(!enabled)) { timeline in
            Canvas { context, size in
                guard enabled, size.width > 1 else { return }
                let p = motion.clock(timeline.date.timeIntervalSinceReferenceDate).truncatingRemainder(dividingBy: 3.2) / 1.6
                guard p < 1 else { return }
                let w: CGFloat = 18, x = -w + (size.width + 2 * w) * p
                let rect = CGRect(x: x - w / 2, y: 0, width: w, height: size.height)
                context.fill(Path(rect), with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.75), color.opacity(0)]),
                                                               startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A slow breath (1.8 s): grows by up to 8% and dims a touch while `enabled`; still otherwise.
private struct Breathe: ViewModifier {
    var enabled: Bool
    var anchor: UnitPoint
    @Environment(\.skin) private var skin

    func body(content: Content) -> some View {
        let motion = SkinMotion.of(skin)
        TimelineView(.animation(minimumInterval: motion.frameInterval, paused: !enabled)) { timeline in
            let t = motion.clock(timeline.date.timeIntervalSinceReferenceDate)
            let s = enabled ? (1 - cos(2 * .pi * t / 1.8)) / 2 : 0
            content.scaleEffect(1 + 0.08 * s, anchor: anchor).opacity(1 - 0.2 * s)
        }
    }
}

extension View {
    /// The lobby object's signature move (`LobbySignature`) while `enabled`.
    func signatureMove(_ feature: Feature, enabled: Bool) -> some View {
        modifier(SignatureMove(signature: LobbySignature.of(feature), phase: LobbySignature.phase(feature), enabled: enabled))
    }
    /// A slow breath while `enabled`.
    func breathes(_ enabled: Bool, anchor: UnitPoint = .center) -> some View { modifier(Breathe(enabled: enabled, anchor: anchor)) }
}

/// The lobby's opening (spec 5.1): on its first appearance after launch, and after the app comes back from the
/// background, the objects pop in one after another and the numeral drops into place, all within 0.7 s. Taps work
/// throughout. Reduce Motion and `--ui-testing` show the final state at once.
enum LobbyOpening {
    /// Whether the very first frame already shows the final state (no opening will play).
    static var skippedAtLaunch: Bool { AmbientMotion.uiTesting || MotionPreference.forced || UIAccessibility.isReduceMotionEnabled }
    /// When each object starts its pop: 找 ETF, 配息, 口袋, 工具 in reading order, 0.06 s apart.
    static func delay(_ feature: Feature) -> Double { LobbySignature.phase(feature) * 4 * 0.06 }
    /// When the numeral starts its drop.
    static let numeralDelay = 0.08

    static func animation(_ skin: Skin, delay: Double) -> Animation { SkinMotion.of(skin).spring.delay(delay) }
}

/// A clock for something that moves for `duration` s out of every `period` s (the first move starting at `offset`):
/// it ticks every `step` s during a move, once just after its end, and then sleeps until the next one begins.
struct MoveSchedule: TimelineSchedule {
    let period: Double, offset: Double, duration: Double, step: Double

    /// The first tick after `time` (seconds since the reference date).
    func next(after time: Double) -> Double {
        var local = (time - offset).truncatingRemainder(dividingBy: period)
        if local < 0 { local += period }
        let windowStart = time - local
        // One step past the move, so a stepped clock has surely left it too before the clock idles.
        let end = windowStart + duration + step
        let result = time < end - 1e-6 ? min(time + step, end) : windowStart + period
        return result > time ? result : time + step
    }

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var time = start.timeIntervalSinceReferenceDate
        var first = true
        return AnyIterator {
            if first { first = false; return start }
            time = next(after: time)
            return Date(timeIntervalSinceReferenceDate: time)
        }
    }

    /// The same clock, stopped while `paused`.
    func paused(_ paused: Bool) -> PausableMoveSchedule { PausableMoveSchedule(base: self, paused: paused) }
}

/// `MoveSchedule` that yields nothing while paused (the view then shows the date it last drew).
struct PausableMoveSchedule: TimelineSchedule {
    let base: MoveSchedule
    let paused: Bool

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        if paused {
            var first = true
            return AnyIterator { if first { first = false; return start }; return nil }
        }
        return base.entries(from: start, mode: mode)
    }
}
