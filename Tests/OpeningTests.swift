import XCTest
@testable import ETFToGo

/// 開場動畫 (2026-11-21 design): its timeline and when it plays.
final class OpeningTests: XCTestCase {
    func testStepAtTime() {
        XCTAssertEqual(Opening.step(at: 0, reduceMotion: false), .ring)
        XCTAssertEqual(Opening.step(at: 0.5, reduceMotion: false), .dollar)
        XCTAssertEqual(Opening.step(at: 1.2, reduceMotion: false), .rays)
        XCTAssertEqual(Opening.step(at: 2.0, reduceMotion: false), .line)
        XCTAssertEqual(Opening.step(at: 3.0, reduceMotion: false), .done)
        XCTAssertEqual(Opening.step(at: 1.6, reduceMotion: false), .title)
    }

    func testReduceMotionIsTheFinalStateAtOnce() {
        for time in [0, 0.5, 1.2, 2.0, 3.0] { XCTAssertEqual(Opening.step(at: time, reduceMotion: true), .done, "at \(time) s") }
    }

    func testPoseStartsHiddenAndEndsOnTheFinalFrameInEverySkin() {
        for id in ["blackgold", "voxel", "stitch", "sketch"] {
            let motion = SkinMotion.of(Skins.named(id))
            let start = OpeningPose.at(0, motion: motion)
            XCTAssertEqual(start.ringOpacity, 0, id)
            XCTAssertEqual(start.ringScale, 0.6, accuracy: 0.0001, id)
            XCTAssertEqual(start.dollarOpacity, 0, id)
            XCTAssertEqual(start.dollarDrop, 1, id)
            XCTAssertEqual(start.raysOpacity, 0, id)
            XCTAssertEqual(start.titleOpacity, 0, id)
            XCTAssertEqual(start.tagOpacity, 0, id)
            XCTAssertEqual(start.lineOpacity, 0, id)
            // Everything has settled by the hold, and stays there.
            XCTAssertEqual(OpeningPose.at(2.6, motion: motion), .final, id)
            XCTAssertEqual(OpeningPose.at(3.0, motion: motion), .final, id)
        }
    }

    func testDollarLandsWithASquash() {
        let motion = SkinMotion.of(Skins.named("blackgold"))
        let landing = Opening.landing(motion)
        XCTAssertEqual(landing, 0.76, accuracy: 0.0001)
        XCTAssertGreaterThan(OpeningPose.at(0.5, motion: motion).dollarDrop, 0, "Still falling at 0.5 s")
        let squashed = OpeningPose.at(landing + 0.08, motion: motion)
        XCTAssertEqual(squashed.dollarDrop, 0, "Landed")
        XCTAssertGreaterThan(squashed.dollarSquash, 0, "Squashes as it lands")
        // The pixel skin lands on a whole step.
        XCTAssertEqual(Opening.landing(SkinMotion.of(Skins.named("voxel"))), 0.875, accuracy: 0.0001)
    }

    func testOnlySketchDrawsItsRaysOn() {
        let sketch = OpeningPose.at(1.2, motion: SkinMotion.of(Skins.named("sketch")))
        XCTAssertGreaterThan(sketch.raysSweep, 0)
        XCTAssertLessThan(sketch.raysSweep, 1)
        for id in ["blackgold", "voxel", "stitch"] {
            XCTAssertEqual(OpeningPose.at(1.2, motion: SkinMotion.of(Skins.named(id))).raysSweep, 1, id)
        }
    }

    func testWhetherTheOpeningShows() {
        // A real launch: always, first or not.
        XCTAssertEqual(Opening.play(firstLaunch: true, arguments: [], fromNotification: false), .animated)
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: [], fromNotification: false), .animated)
        // UI tests: the first launch shows the final frame at once; later launches skip it entirely.
        XCTAssertEqual(Opening.play(firstLaunch: true, arguments: ["--ui-testing"], fromNotification: false), .still)
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: ["--ui-testing", "--skip-onboarding"], fromNotification: false), .off)
        // --opening forces it under --ui-testing, and changes nothing without it.
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: ["--ui-testing", "--opening"], fromNotification: false), .animated)
        XCTAssertEqual(Opening.play(firstLaunch: true, arguments: ["--ui-testing", "--opening"], fromNotification: false), .animated)
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: ["--opening"], fromNotification: false), .animated)
        // Launched from a notification: no opening; a first launch still needs its splash to start, so its final frame.
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: [], fromNotification: true), .off)
        XCTAssertEqual(Opening.play(firstLaunch: true, arguments: [], fromNotification: true), .still)
    }

    func testOnlyAForcedUITestOpeningHolds() {
        XCTAssertTrue(Opening.holds(["--ui-testing", "--opening"]))
        XCTAssertFalse(Opening.holds(["--opening"]))
        XCTAssertFalse(Opening.holds(["--ui-testing"]))
        XCTAssertFalse(Opening.holds([]))
    }

    /// The splash's first launch: `--open splash` (screenshots) is a first launch, so its final frame at once.
    func testOpenSplashIsTheStillFinalFrame() {
        let arguments = ["--ui-testing", "--skip-onboarding", "--open", "splash"]
        let start = Onboarding.start(arguments, onboarded: true)
        XCTAssertEqual(start, .splash)
        XCTAssertEqual(Opening.play(firstLaunch: start == .splash, arguments: arguments, fromNotification: false), .still)
    }
}
