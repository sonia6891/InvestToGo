import AVFoundation
import CoreHaptics
import SwiftUI
import UIKit

/// Short sounds: each skin's own confirm sound (spec 7.1: 黑金「咚」, 像素「叮」, 縫線「喀嚓」, 手繪「沙沙」), read from
/// App/Resources/Sounds/<feedback.sound>.caf (made by Scripts/make_sounds.py), plus the synthesised coin chime and tick.
@MainActor enum SoundFX {
    private static var players: [String: AVAudioPlayer] = [:]

    /// The skin's confirm sound in the app bundle.
    nonisolated static func url(for skin: Skin) -> URL? { Bundle.main.url(forResource: skin.feedback.sound, withExtension: "caf") }

    /// The skin's confirm sound; silent when 音效 is off in 設定 (`pocket.sound`).
    static func confirm(_ skin: Skin, enabled: Bool) {
        guard enabled, let url = url(for: skin) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let player: AVAudioPlayer
            if let cached = players[skin.feedback.sound] { player = cached } else {
                player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[skin.feedback.sound] = player
            }
            player.currentTime = 0
            player.play()
        } catch { /* Sound is decoration: a device that cannot play it stays silent. */ }
    }

    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var ready = false

    static func coin(enabled: Bool) { play([(1318.5, 0, 0.22), (1975.5, 0.075, 0.18), (2637, 0.15, 0.08)], length: 0.6, wave: .triangle, enabled: enabled) }
    static func tick(enabled: Bool) { play([(1800, 0, 0.07)], length: 0.08, wave: .square, enabled: enabled) }

    private enum Wave { case triangle, square }
    private static func play(_ notes: [(frequency: Double, delay: Double, volume: Double)], length: Double, wave: Wave, enabled: Bool) {
        guard enabled else { return }
        do {
            if !ready {
                try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
                ready = true
            }
            if !engine.isRunning { try engine.start() }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(44_100 * length)) else { return }
            buffer.frameLength = buffer.frameCapacity
            let samples = buffer.floatChannelData![0]
            for i in 0..<Int(buffer.frameLength) {
                let t = Double(i) / 44_100
                var value = 0.0
                for note in notes where t >= note.delay {
                    let local = t - note.delay
                    let phase = (local * note.frequency).truncatingRemainder(dividingBy: 1)
                    let shape = wave == .triangle ? 4 * abs(phase - 0.5) - 1 : (phase < 0.5 ? 1 : -1)
                    let envelope = min(local / 0.008, 1) * exp(-local * 9)
                    value += shape * note.volume * envelope
                }
                samples[i] = Float(max(-1, min(1, value)))
            }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        } catch { /* Sound is decoration: a device that cannot play it stays silent. */ }
    }
}

/// One impact of a skin's confirm haptic: when (seconds after the first), which generator and how hard.
struct HapticPulse: Equatable {
    var delay: Double
    var style: UIImpactFeedbackGenerator.FeedbackStyle
    var intensity: CGFloat
}

/// Custom haptics, with the standard impact generator where Core Haptics is unavailable.
@MainActor enum Haptics {
    /// Each skin's confirm haptic (spec 7.1 震動): heavy＝one heavy, triple＝three rigid 60 ms apart, tap＝one light,
    /// faint＝one soft at 0.3.
    nonisolated static func pulses(_ kind: SkinFeedback.HapticKind) -> [HapticPulse] {
        switch kind {
        case .heavy: return [HapticPulse(delay: 0, style: .heavy, intensity: 1)]
        case .triple: return [0, 0.06, 0.12].map { HapticPulse(delay: $0, style: .rigid, intensity: 1) }
        case .tap: return [HapticPulse(delay: 0, style: .light, intensity: 1)]
        case .faint: return [HapticPulse(delay: 0, style: .soft, intensity: 0.3)]
        }
    }

    static func confirm(_ kind: SkinFeedback.HapticKind) {
        let steps = pulses(kind)
        // The generators are made and used on the main actor, after each pulse's delay.
        Task { @MainActor in
            var elapsed = 0.0
            for pulse in steps {
                if pulse.delay > elapsed {
                    try? await Task.sleep(for: .milliseconds(Int(((pulse.delay - elapsed) * 1000).rounded())))
                    elapsed = pulse.delay
                }
                UIImpactFeedbackGenerator(style: pulse.style).impactOccurred(intensity: pulse.intensity)
            }
        }
    }

    private static var engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine = try? CHHapticEngine(); engine?.isAutoShutdownEnabled = true
        return engine
    }()

    /// A sharp tap as the coin lands, then a short rumble while the shards fly.
    static func coinDrop() {
        play([CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 1), .init(parameterID: .hapticSharpness, value: 0.8)], relativeTime: 0),
              CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 0.5), .init(parameterID: .hapticSharpness, value: 0.2)], relativeTime: 0.04, duration: 0.18)],
             fallback: .heavy)
    }
    static func tick() {
        play([CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 0.5), .init(parameterID: .hapticSharpness, value: 1)], relativeTime: 0)],
             fallback: .light)
    }
    private static func play(_ events: [CHHapticEvent], fallback: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard let engine else { UIImpactFeedbackGenerator(style: fallback).impactOccurred(); return }
        do {
            try engine.start()
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: 0)
        } catch { UIImpactFeedbackGenerator(style: fallback).impactOccurred() }
    }
}

/// A skin's confirm: its sound (when 音效 is on) and its haptic.
@MainActor enum ConfirmFeedback {
    static func confirm(_ skin: Skin) {
        SoundFX.confirm(skin, enabled: SkinStore.shared.soundOn)
        Haptics.confirm(skin.feedback.haptic)
    }
}

/// Reduce Motion: the system setting, or `--reduce-motion` with `--ui-testing` (treated as the setting turned on).
enum MotionPreference {
    static let forced: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--reduce-motion")
    }()
}

extension EnvironmentValues {
    /// Read instead of `accessibilityReduceMotion` everywhere, so `--reduce-motion` reaches every screen.
    var motionReduced: Bool { accessibilityReduceMotion || MotionPreference.forced }
}
