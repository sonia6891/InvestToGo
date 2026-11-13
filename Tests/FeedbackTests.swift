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
            guard let url else { continue }
            // A real, short, playable sound: the generated CAF opens and lasts a fraction of a second.
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertGreaterThan(seconds, 0.03, "\(skin.id): \(skin.feedback.sound).caf has sound in it")
            XCTAssertLessThan(seconds, 1, "\(skin.id): \(skin.feedback.sound).caf is a short confirm sound")
        }
    }
}
