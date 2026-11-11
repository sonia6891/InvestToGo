import AVFoundation
import CoreHaptics
import UIKit

/// Short synthesised sounds, the same tones as the 3D concept page: a three-note coin chime and a soft tick.
@MainActor enum SoundFX {
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

/// Custom haptics, with the standard impact generator where Core Haptics is unavailable.
@MainActor enum Haptics {
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
