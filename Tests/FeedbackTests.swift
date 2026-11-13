import XCTest
import AVFoundation
import UIKit
@testable import ETFToGo

/// Each skin's confirm feedback (spec 7.1 音效・震動): its own sound file in the app, and its own haptic pattern.
final class FeedbackTests: XCTestCase {
    func testEverySkinSoundFileExists() throws {
        XCTAssertEqual(Set(Skins.all.map(\.feedback.sound)), ["thud", "chip", "snip", "scribble"])
        for skin in Skins.all {
            let url = Bundle.main.url(forResource: skin.feedback.sound, withExtension: "caf")
            XCTAssertNotNil(url, "\(skin.id): \(skin.feedback.sound).caf is in the app")
            XCTAssertEqual(SoundFX.url(for: skin), url, "\(skin.id): SoundFX plays the skin's own file")
            guard let url else { continue }
            // A real, short, playable sound: the generated CAF opens and lasts a fraction of a second.
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertGreaterThan(seconds, 0.03, "\(skin.id): \(skin.feedback.sound).caf has sound in it")
            XCTAssertLessThan(seconds, 1, "\(skin.id): \(skin.feedback.sound).caf is a short confirm sound")
        }
    }

    /// heavy＝one heavy, triple＝three rigid 60 ms apart, tap＝one light, faint＝one soft at 0.3.
    @MainActor func testHapticPatternPerKind() {
        XCTAssertEqual(Haptics.pulses(.heavy), [HapticPulse(delay: 0, style: .heavy, intensity: 1)])
        XCTAssertEqual(Haptics.pulses(.triple), [HapticPulse(delay: 0, style: .rigid, intensity: 1),
                                                 HapticPulse(delay: 0.06, style: .rigid, intensity: 1),
                                                 HapticPulse(delay: 0.12, style: .rigid, intensity: 1)])
        XCTAssertEqual(Haptics.pulses(.tap), [HapticPulse(delay: 0, style: .light, intensity: 1)])
        XCTAssertEqual(Haptics.pulses(.faint), [HapticPulse(delay: 0, style: .soft, intensity: 0.3)])
        XCTAssertEqual(Skins.named("blackgold").feedback.haptic, .heavy)
        XCTAssertEqual(Skins.named("voxel").feedback.haptic, .triple)
        XCTAssertEqual(Skins.named("stitch").feedback.haptic, .tap)
        XCTAssertEqual(Skins.named("sketch").feedback.haptic, .faint)
    }

    /// The coin drop follows the art kind, never the skin id: 3D skins drop a coin with shards, vector skins pop
    /// their picture with 「+1」 (spec 7.1 投幣動畫, first version).
    func testCoinDropStyleFollowsArtKind() {
        XCTAssertEqual(CoinDropStyle(Skins.named("blackgold")), .coinAndShards)
        XCTAssertEqual(CoinDropStyle(Skins.named("voxel")), .coinAndShards)
        XCTAssertEqual(CoinDropStyle(Skins.named("stitch")), .popPlusOne)
        XCTAssertEqual(CoinDropStyle(Skins.named("sketch")), .popPlusOne)
    }

    /// 「離線中 · 顯示 MM/DD HH:mm 的資料」.
    @MainActor func testOfflineBarText() {
        var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 12; parts.hour = 9; parts.minute = 5
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        XCTAssertEqual(OfflineBar.text(date), "離線中 · 顯示 11/12 09:05 的資料")
        XCTAssertEqual(OfflineBar.text(nil), "離線中 · 顯示上次的資料")
    }
}
