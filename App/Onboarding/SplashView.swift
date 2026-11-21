import SwiftUI

/// 開機 (spec 5.1) and the opening played on every cold launch (2026-11-21 design): the stage ring springs open, the
/// 3D 「$」 drops in and lands, the skin's rays sweep out, then 「ETF 袋著走」, the skin's tag and 「存 ETF，也存下好習慣。」.
/// `ending` says what follows: on the first launch 「→ 輕點開始 ←」 and a tap anywhere starts; on later launches it goes
/// on by itself. 略過 (or a tap anywhere) skips: to the final frame on the first launch, to the lobby on later ones.
struct SplashView: View {
    enum Ending { case tapToStart, continues }

    let play: OpeningPlay
    let ending: Ending
    let onStart: () -> Void

    @Environment(\.skin) private var skin
    @Environment(\.motionReduced) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var power = PowerState.shared
    @ObservedObject private var launch = OpeningLaunch.shared
    /// When the timeline started: the first time the app is in front, so a launch in the background does not use it up.
    @State private var began: Date?
    /// The timeline is over: the final frame stays (and, on the first launch, 輕點開始 shows).
    @State private var ended: Bool
    /// `onStart` was called for a later launch: nothing more happens here.
    @State private var left = false
    /// The whole screen's opacity: 0 until the timeline starts; Reduce Motion fades it in.
    @State private var shown: Double

    init(play: OpeningPlay = .still, ending: Ending = .tapToStart, onStart: @escaping () -> Void) {
        self.play = play
        self.ending = ending
        self.onStart = onStart
        let animated = play == .animated
        _ended = State(initialValue: !animated)
        _shown = State(initialValue: animated ? 0 : 1)
    }

    private var animated: Bool { play == .animated }
    private var motion: SkinMotion { SkinMotion.of(skin) }
    private var running: Bool { animated && began != nil && !ended && !reduceMotion }

    var body: some View {
        // At the display's rate; the stepped (pixel) skin redraws once a step.
        TimelineView(.animation(minimumInterval: motion.stepped ? motion.frameInterval : nil, paused: !running)) { timeline in
            content(pose(at: timeline.date))
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { if showsSkip { skipButton } }
        .opacity(shown)
        .contentShape(Rectangle())
        .onTapGesture(perform: tapped)
        .background(skin.color(\.page).ignoresSafeArea())
        .onAppear { if phase == .active { begin() } }
        .onChange(of: phase) { _, value in
            if value == .active { begin() }
            // Sent to the background part-way: it never replays on return, so it ends here.
            if value == .background, began != nil { finishNow(background: true) }
        }
        // A scene that never reports itself active (it should) still starts after a second.
        .task {
            guard animated else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled, began == nil, phase != .background { begin() }
        }
        .task(id: began) { if began != nil { await run() } }
        // A cold launch from a notification: iOS may say so only after the first frame.
        .onChange(of: launch.fromNotification) { _, value in if value { finishNow() } }
    }

    // MARK: Layout

    private func content(_ pose: OpeningPose) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 16)
            stage(pose)
                .padding(.bottom, 22)
            Text("ETF 袋著走").skinFont(.title(34)).foregroundStyle(skin.color(\.ink))
                .offset(y: 24 * (1 - pose.titleRise))
                .opacity(pose.titleOpacity)
                .accessibilityAddTraits(.isHeader)
            SkinTag(skin.name)
                .scaleEffect(pose.tagScale)
                .opacity(pose.tagOpacity)
            Text("存 ETF，也存下好習慣。").skinFont(.body(15)).foregroundStyle(skin.color(\.sub)).padding(.top, 4)
                .opacity(pose.lineOpacity)
            Spacer(minLength: 16)
            if ending == .tapToStart && ended {
                startButton.transition(.opacity)
            } else {
                // Holds 輕點開始's place, so the frame does not move when it appears.
                Color.clear.frame(width: 200, height: 44).accessibilityHidden(true)
            }
        }
    }

    /// The rays, the stage ring and the 「$」, each moving on its own. Decorative.
    private func stage(_ pose: OpeningPose) -> some View {
        Color.clear.frame(width: 220, height: 220)
            .background {
                SkinDecor(page: .splash).frame(width: 390, height: 320)
                    .mask { OpeningSweep(progress: pose.raysSweep) }
                    .scaleEffect(pose.raysScale)
                    .rotationEffect(.degrees(pose.raysTurn))
                    .opacity(pose.raysOpacity)
            }
            .overlay {
                SkinStage(size: 220) { Color.clear }
                    .scaleEffect(pose.ringScale)
                    .opacity(pose.ringOpacity)
            }
            .overlay {
                SkinImage(.heroDollar).padding(42).frame(width: 220, height: 220)
                    .scaleEffect(x: 1 + pose.dollarSquash, y: 1 - pose.dollarSquash, anchor: .bottom)
                    .offset(y: -Opening.dropHeight * pose.dollarDrop)
                    .opacity(pose.dollarOpacity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var startButton: some View {
        Button(action: onStart) {
            StartLabel(breathing: AmbientMotion.allowed(reduceMotion: reduceMotion, lowPower: power.lowPower,
                                                        uiTesting: AmbientMotion.uiTesting, onScreen: true, active: phase == .active))
                .frame(minWidth: 200, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("輕點開始")
        .accessibilityIdentifier("splash")
    }

    /// 略過 while the opening plays (on later launches until it has gone).
    private var showsSkip: Bool { animated && (ending == .continues || !ended) }

    private var skipButton: some View {
        Button(action: skip) {
            Text("略過").skinFont(.title(15)).foregroundStyle(skin.color(\.sub))
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("略過")
        .accessibilityIdentifier("opening-skip")
        .padding(.trailing, 8)
    }

    // MARK: Timeline

    private func pose(at date: Date) -> OpeningPose {
        if !animated || ended || reduceMotion { return .final }
        guard let began else { return .at(0, motion: motion) }
        return .at(motion.clock(date.timeIntervalSince(began)), motion: motion)
    }

    private func begin() {
        guard animated, began == nil, !ended else { return }
        // The notification may have been heard after the launch decided, before this first start.
        if launch.fromNotification { finishNow(); return }
        launch.markPlayed()
        began = Date()
        if reduceMotion {
            // No movement: everything fades in together; the first launch's 輕點開始 with it.
            withAnimation(.easeOut(duration: Opening.reducedFade)) {
                shown = 1
                if ending == .tapToStart { ended = true }
            }
        } else {
            shown = 1
        }
    }

    /// The landing haptic, then the end of the timeline: 輕點開始 on the first launch, the lobby on later ones.
    private func run() async {
        if reduceMotion {
            guard ending == .continues else { return }
            try? await Task.sleep(for: .seconds(Opening.reducedLength))
        } else {
            let landing = Opening.landing(motion)
            try? await Task.sleep(for: .seconds(landing))
            guard !Task.isCancelled else { return }
            if !ended { Haptics.confirm(.tap) }
            try? await Task.sleep(for: .seconds(Opening.length - landing))
        }
        guard !Task.isCancelled, !left else { return }
        switch ending {
        case .tapToStart:
            if !ended { withAnimation(.easeOut(duration: 0.4)) { ended = true } }
        case .continues:
            if Opening.holds(ProcessInfo.processInfo.arguments) { ended = true } else { leave() }
        }
    }

    /// 略過: the first launch jumps to the final frame with 輕點開始; later launches go straight to the lobby.
    private func skip() {
        switch ending {
        case .tapToStart:
            guard !ended else { return }
            withAnimation(.easeOut(duration: 0.25)) { ended = true }
        case .continues:
            leave()
        }
    }

    /// A tap anywhere: skips while the opening plays; on the first launch's final frame, starts.
    private func tapped() {
        if ending == .tapToStart && ended { onStart() } else { skip() }
    }

    /// Ends at once, without the fade (sent to the background, or a launch from a notification).
    private func finishNow(background: Bool = false) {
        guard animated else { return }
        shown = 1
        switch ending {
        case .tapToStart: ended = true
        case .continues:
            leave()
            // The lobby is built already in the background and never hears it go there: the 到價提醒 background check
            // it would have asked for is asked for here (`RootView` does the same on going to the background).
            if background { PriceAlertMonitor.scheduleNext() }
        }
    }

    private func leave() {
        guard !left else { return }
        left = true
        ended = true
        onStart()
    }
}

/// 「→ 輕點開始 ←」, its arrows breathing toward the centre while ambient motion is allowed (in the skin's steps).
private struct StartLabel: View {
    var breathing: Bool
    @Environment(\.skin) private var skin

    var body: some View {
        let motion = SkinMotion.of(skin)
        TimelineView(.animation(minimumInterval: motion.frameInterval, paused: !breathing)) { timeline in
            let t = motion.clock(timeline.date.timeIntervalSinceReferenceDate)
            let inward = breathing ? 4 * CGFloat(1 - cos(2 * .pi * t / 1.6)) / 2 : 0
            HStack(spacing: 0) {
                Text("→ ").offset(x: inward)
                Text("輕點開始")
                Text(" ←").offset(x: -inward)
            }
            .skinFont(.mono(13)).foregroundStyle(skin.color(\.dim))
        }
    }
}

/// The share of a turn revealed from 12 o'clock: sketch's rays drawn on like strokes. A full rectangle at 1.
private struct OpeningSweep: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        guard progress < 1 else { return Path(rect) }
        var path = Path()
        guard progress > 0 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY), radius = hypot(rect.width, rect.height)
        path.move(to: centre)
        path.addArc(center: centre, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        path.closeSubpath()
        return path
    }
}
