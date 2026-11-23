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
        for id in Skins.all.map(\.id) {
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
        XCTAssertEqual(landing, 0.91, accuracy: 0.0001)
        XCTAssertGreaterThan(OpeningPose.at(0.5, motion: motion).dollarDrop, 0, "Still falling at 0.5 s")
        let squashed = OpeningPose.at(landing + 0.08, motion: motion)
        XCTAssertEqual(squashed.dollarDrop, 0, "Landed")
        XCTAssertGreaterThan(squashed.dollarSquash, 0, "Squashes as it lands")
        // The pixel skin lands on a whole step.
        XCTAssertEqual(Opening.landing(SkinMotion.of(Skins.named("voxel"))), 1.0, accuracy: 0.0001)
    }

    /// The owner's drop (2026-11-21): 180 pt, seen falling from the first frame of its step, 0.35 f + 0.65 f².
    func testDollarIsSeenFalling() {
        let motion = SkinMotion.of(Skins.named("blackgold"))
        XCTAssertEqual(Opening.dropHeight, 180)
        XCTAssertEqual(Opening.fallShare, 0.68)
        XCTAssertEqual(Opening.squash, 0.14)
        XCTAssertEqual(OpeningPose.at(0.39, motion: motion).dollarOpacity, 0, "Invisible before 0.4 s")
        let early = OpeningPose.at(0.45, motion: motion)
        XCTAssertLessThan(early.dollarDrop, 1, "Moving at once, not hanging at the top")
        XCTAssertGreaterThan(early.dollarOpacity, 0)
        XCTAssertEqual(OpeningPose.at(0.4 + 0.75 * 0.2, motion: motion).dollarOpacity, 1, accuracy: 0.0001, "Faded in over the first 20%")
        let f = 0.5, u = f * Opening.fallShare
        XCTAssertEqual(OpeningPose.at(0.4 + 0.75 * u, motion: motion).dollarDrop, 1 - (0.35 * f + 0.65 * f * f), accuracy: 0.0001)
        XCTAssertEqual(Opening.step(at: 0.92, reduceMotion: false), .dollar, "The rays open just after the landing")
        XCTAssertEqual(Opening.step(at: 0.96, reduceMotion: false), .rays)
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

    /// Once begun in this process, a scene built again does not replay it.
    func testPlaysOncePerProcess() {
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: [], fromNotification: false, alreadyPlayed: true), .off)
        XCTAssertEqual(Opening.play(firstLaunch: true, arguments: [], fromNotification: false, alreadyPlayed: true), .still)
        XCTAssertEqual(Opening.play(firstLaunch: false, arguments: ["--ui-testing", "--opening"], fromNotification: false, alreadyPlayed: true), .off)
    }

    /// The design's table, the one source the poses, the landing and `step(at:)` read.
    func testTimelineIsTheDesignTable() {
        XCTAssertEqual(Opening.window(.ring), OpeningWindow(start: 0, length: 0.6))
        XCTAssertEqual(Opening.window(.dollar), OpeningWindow(start: 0.4, length: 0.75))
        XCTAssertEqual(Opening.window(.rays), OpeningWindow(start: 0.95, length: 0.7))
        XCTAssertEqual(Opening.window(.title), OpeningWindow(start: 1.4, length: 0.8))
        XCTAssertEqual(Opening.window(.line), OpeningWindow(start: 2.0, length: 0.6))
        XCTAssertEqual(Opening.length, 3.0)
        let dollar = Opening.window(.dollar)
        XCTAssertEqual(Opening.landing(SkinMotion.of(Skins.named("blackgold"))), dollar.start + dollar.length * Opening.fallShare, accuracy: 0.0001)
    }

    /// Each part is still hidden just before its step begins and moving just after: the poses follow the table that
    /// `step(at:)` reads.
    func testEachPartMovesInItsOwnStep() {
        let motion = SkinMotion.of(Skins.named("blackgold"))
        let parts: [(OpeningStep, (OpeningPose) -> Double)] = [
            (.dollar, { $0.dollarOpacity }), (.rays, { $0.raysOpacity }), (.title, { $0.titleOpacity }), (.line, { $0.lineOpacity }),
        ]
        for (step, value) in parts {
            let start = Opening.window(step).start
            XCTAssertEqual(value(OpeningPose.at(start - 0.01, motion: motion)), 0, "\(step) is hidden before it begins")
            XCTAssertGreaterThan(value(OpeningPose.at(start + 0.05, motion: motion)), 0, "\(step) moves once it begins")
            XCTAssertEqual(Opening.step(at: start + 0.05, reduceMotion: false), step)
        }
        XCTAssertGreaterThan(OpeningPose.at(0.05, motion: motion).ringOpacity, 0, "The ring opens at once")
        // Everything has settled by the end of the last moving step.
        XCTAssertEqual(OpeningPose.at(Opening.window(.line).end, motion: motion), .final)
    }

    /// The pixel skin has no bounce: its springs never pass their mark.
    func testSettleWithoutBounceNeverOvershoots() {
        for i in 0...100 { XCTAssertLessThanOrEqual(Opening.settle(Double(i) / 100, bounce: 0), 1) }
        XCTAssertGreaterThan((0...100).map { Opening.settle(Double($0) / 100, bounce: 0.55) }.max() ?? 0, 1, "Stitch still overshoots")
    }
}
