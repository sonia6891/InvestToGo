import SwiftUI

// The shared motion kit: each skin's motion personality, the gate for ambient (always-on) motion, a pressable button
// style, staggered entrances, an idle bob and rising particles. Decorative only: never tied to price movement, never
// blocking taps, hidden from VoiceOver.

enum MotionParticle { case dust, square, dot, stroke }

/// How a skin moves: smooth and rich (black-gold), stepped like 8-bit (voxel), bouncy (stitch), jittery (sketch).
struct SkinMotion: Equatable {
    var bounce: Double
    var stepped: Bool
    var stepsPerSecond: Double
    var bobAmplitude: CGFloat
    var particle: MotionParticle
    var jitter: Bool

    static func of(_ skin: Skin) -> SkinMotion {
        switch skin.id {
        case "voxel": return SkinMotion(bounce: 0, stepped: true, stepsPerSecond: 8, bobAmplitude: 6, particle: .square, jitter: false)
        case "stitch": return SkinMotion(bounce: 0.55, stepped: false, stepsPerSecond: 0, bobAmplitude: 6, particle: .dot, jitter: false)
        case "sketch": return SkinMotion(bounce: 0.25, stepped: false, stepsPerSecond: 0, bobAmplitude: 6, particle: .stroke, jitter: true)
        default: return SkinMotion(bounce: 0.2, stepped: false, stepsPerSecond: 0, bobAmplitude: 6, particle: .dust, jitter: false)
        }
    }

    /// The skin's own spring for presses and entrances (a short linear step for the stepped skin).
    var spring: Animation { stepped ? .linear(duration: 0.12) : .spring(response: 0.32, dampingFraction: max(0.35, 1 - bounce)) }
}

/// Ambient motion runs only when nothing argues against it.
enum AmbientMotion {
    static func allowed(reduceMotion: Bool, lowPower: Bool, uiTesting: Bool, onScreen: Bool, active: Bool) -> Bool {
        !reduceMotion && !lowPower && !uiTesting && onScreen && active
    }
    /// `--ui-testing`, read once.
    static let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
}

/// Low Power Mode, observed so ambient motion stops while it is on.
final class PowerState: ObservableObject {
    static let shared = PowerState()
    @Published private(set) var lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    private init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// Squashes while pressed, with the skin's spring; under Reduce Motion only dims. The label keeps its own accessibility.
struct PressableStyle: ButtonStyle {
    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .scaleEffect(x: pressed && !reduceMotion ? 1.12 : 1, y: pressed && !reduceMotion ? 0.88 : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? nil : SkinMotion.of(skin).spring, value: pressed)
    }
}

private struct EnterStagger: ViewModifier {
    var index: Int
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.skin) private var skin
    @State private var shown = false

    func body(content: Content) -> some View {
        if AmbientMotion.uiTesting {
            content
        } else {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 14)
                .onAppear {
                    guard !shown else { return }
                    let delay = Double(min(max(index, 0), 7)) * 0.05
                    withAnimation((reduceMotion ? Animation.easeOut(duration: 0.2) : SkinMotion.of(skin).spring).delay(delay)) { shown = true }
                }
        }
    }
}

private struct AmbientBob: ViewModifier {
    var phase: Double
    var enabled: Bool
    @Environment(\.skin) private var skin

    func body(content: Content) -> some View {
        let motion = SkinMotion.of(skin)
        TimelineView(.animation(paused: !enabled)) { timeline in
            let o = Self.offsets(time: timeline.date.timeIntervalSinceReferenceDate, phase: phase, motion: motion, enabled: enabled)
            content.offset(y: o.dy).rotationEffect(.degrees(o.rotation))
        }
    }

    private static func offsets(time: Double, phase: Double, motion: SkinMotion, enabled: Bool) -> (dy: CGFloat, rotation: Double) {
        guard enabled else { return (0, 0) }
        let t = motion.stepped ? (time * motion.stepsPerSecond).rounded(.down) / motion.stepsPerSecond : time
        let cycle = (t / 3 + phase).truncatingRemainder(dividingBy: 1)
        var dy = CGFloat(sin(cycle * 2 * .pi)) * motion.bobAmplitude
        var rotation = 0.0
        if motion.jitter {
            // A small change every 0.25 s, different per phase.
            let tick = Int((time / 0.25).rounded(.down)) &+ Int(phase * 1000)
            let r = Double((tick &* 2654435761) & 0xFF) / 255
            rotation = (r - 0.5) * 2.4
            dy += CGFloat(r - 0.5) * 1.5
        }
        return (dy, rotation)
    }
}

extension View {
    /// Rises into place on first appear, `index × 0.05 s` apart (indexes above 7 share the delay of 7). Reduce Motion
    /// fades only; `--ui-testing` skips it.
    func enterStagger(_ index: Int) -> some View { modifier(EnterStagger(index: index)) }
    /// A slow idle up/down bob in the skin's style; `phase` (0...1) offsets the cycle. Still when disabled.
    func ambientBob(phase: Double, enabled: Bool) -> some View { modifier(AmbientBob(phase: phase, enabled: enabled)) }
}

/// Up to 14 small shapes in the skin's style drifting up and fading. Decorative: no hit testing, hidden from VoiceOver.
struct AmbientParticles: View {
    var enabled: Bool
    @Environment(\.skin) private var skin
    private static let count = 14

    var body: some View {
        let motion = SkinMotion.of(skin)
        let tint = skin.color(\.accent)
        TimelineView(.animation(paused: !enabled)) { timeline in
            Canvas { context, size in
                guard enabled, size.width > 0, size.height > 0 else { return }
                let now = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<Self.count {
                    let period = 6.0 + Double(i % 5)
                    let p = ((now / period) + Double(i) / Double(Self.count)).truncatingRemainder(dividingBy: 1)
                    let seed = Double((i * 7919) % 97) / 97
                    let x = size.width * (0.05 + 0.9 * seed) + CGFloat(sin(p * 2 * .pi + seed * 6)) * 8
                    let y = size.height * (1.05 - 1.1 * p)
                    let s: CGFloat = 3 + CGFloat(i % 3) * 1.5
                    let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                    var layer = context
                    layer.opacity = 0.5 * sin(p * .pi)
                    switch motion.particle {
                    case .square: layer.fill(Path(rect), with: .color(tint))
                    case .dot, .dust: layer.fill(Path(ellipseIn: rect), with: .color(tint))
                    case .stroke:
                        var path = Path()
                        path.move(to: CGPoint(x: x - s, y: y + s / 2))
                        path.addLine(to: CGPoint(x: x + s, y: y - s / 2))
                        layer.stroke(path, with: .color(tint), lineWidth: 1.2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
