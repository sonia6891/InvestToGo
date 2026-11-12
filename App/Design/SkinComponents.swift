import SwiftUI

// The skin component kit. Each component reads the current skin from the environment and switches on
// `skin.style.<kind>`; screens use these and never ask which skin is active. Values follow the approved
// four-skin canvas (black-gold / pixel / stitch / sketch).
//
// Chips, the search field and cards have no kind of their own in skins.json: they follow `style.button`, the
// family they are drawn with on the canvas.

// MARK: - Buttons

/// The skin's button chrome around any label: hexagon (black-gold), block with hard shadow and white frame (pixel),
/// red paper with a sewn seam (stitch), wobbly hand-drawn box (sketch). Primary is the filled call to action.
struct SkinButtonChrome<Label: View>: View {
    @Environment(\.skin) private var skin
    var primary: Bool
    var pressed: Bool
    /// Side padding; nil uses the skin's own. Smaller when two buttons share a row.
    var horizontal: CGFloat?
    /// Seed of the hand-drawn outline.
    var seed: UInt64
    let label: Label

    init(primary: Bool, pressed: Bool = false, horizontal: CGFloat? = nil, seed: UInt64 = 1, @ViewBuilder label: () -> Label) {
        self.primary = primary; self.pressed = pressed; self.horizontal = horizontal; self.seed = seed; self.label = label()
    }

    var body: some View {
        styled
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }

    @ViewBuilder private var styled: some View {
        switch skin.style.button {
        case .hex:
            // Primary: solid ink hexagon, dark text. Secondary: outline; fills with ink while pressed.
            let filled = primary || pressed
            label.skinFont(.title(primary ? 16 : 15)).tracking(primary ? 2 : 1.5)
                .foregroundStyle(filled ? skin.color(\.page) : skin.color(\.ink))
                .padding(.horizontal, horizontal ?? (primary ? 46 : 32)).padding(.vertical, primary ? 13 : 11)
                .background(HexagonShape().fill(filled ? skin.color(\.ink) : skin.color(\.page)))
                .overlay(HexagonShape().strokeBorder(skin.color(\.ink), lineWidth: 2))
        case .pixelBlock:
            // Primary: accent block, 2pt white frame, 4pt hard shadow, "▶" lead. Secondary: cyan outline block.
            HStack(spacing: 8) {
                // U+FE0E keeps the triangle a text glyph instead of the play-button emoji.
                if primary { Text("\u{25B6}\u{FE0E}").accessibilityHidden(true) }
                label
            }
            .skinFont(.title(primary ? 18 : 16))
            .foregroundStyle(primary ? skin.color(\.ink) : skin.extra(1, or: \.accent))
            .padding(.horizontal, horizontal ?? (primary ? 30 : 24)).padding(.vertical, primary ? 11 : 9)
            .background(Rectangle().fill(primary ? skin.color(\.accent) : skin.color(\.page)).hardShadow(skin.extra(2, or: \.line)))
            .overlay(Rectangle().strokeBorder(primary ? skin.color(\.ink) : skin.extra(1, or: \.accent), lineWidth: primary ? 2 : 3))
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
        case .paperStitch:
            // Primary: accent paper, cream seam. Secondary: cream paper, navy seam and text.
            let navy = skin.extra(0, or: \.ink)
            label.skinFont(.title(primary ? 16 : 15)).tracking(primary ? 2 : 1)
                .foregroundStyle(primary ? skin.color(\.card) : navy)
                .padding(.horizontal, horizontal ?? (primary ? 40 : 26)).padding(.vertical, primary ? 13 : 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(primary ? skin.color(\.accent) : skin.color(\.card)).paperShadow())
                .overlay(StitchSeam(color: primary ? skin.color(\.card) : navy, cornerRadius: 10, inset: 6, lineWidth: 2))
        case .sketchBox:
            // A wobbly ink box; the primary one is coloured in with the highlighter yellow.
            label.skinFont(.title(primary ? 17 : 15))
                .foregroundStyle(skin.color(\.ink))
                .padding(.horizontal, horizontal ?? (primary ? 40 : 26)).padding(.vertical, primary ? 12 : 9)
                .background(SketchBoxShape(seed: seed).fill(primary ? skin.color(\.accent) : (pressed ? skin.color(\.line) : Color.clear)))
                .overlay(SketchBoxShape(seed: seed).stroke(skin.color(\.ink), style: StrokeStyle(lineWidth: primary ? 2.5 : 2, lineCap: .round, lineJoin: .round)))
        }
    }
}

/// The skin's button look for `Button` and `NavigationLink`.
struct SkinButtonStyle: ButtonStyle {
    var primary = true
    var horizontal: CGFloat? = nil
    var seed: UInt64 = 1
    func makeBody(configuration: Configuration) -> some View {
        SkinButtonChrome(primary: primary, pressed: configuration.isPressed, horizontal: horizontal, seed: seed) { configuration.label }
    }
}

/// A text button in the skin's style, at least 44×44.
struct SkinButton: View {
    let title: String
    var primary: Bool
    let action: () -> Void
    init(_ title: String, primary: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.primary = primary; self.action = action
    }
    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(SkinButtonStyle(primary: primary, seed: SkinSeed.of(title)))
    }
}

// MARK: - Tags and chips

/// A small label: hexagon outline (black-gold), yellow block with pink hard shadow (pixel), cream paper strip with a
/// red seam (stitch), highlighter stroke under the text (sketch).
struct SkinTag: View {
    @Environment(\.skin) private var skin
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        switch skin.style.tag {
        case .hexOutline:
            // Tags are short, so their ends are cut deeper than buttons' (half the height, as on the canvas).
            Text(text).skinFont(.title(11)).tracking(0.9)
                .foregroundStyle(skin.color(\.ink))
                .padding(.horizontal, 15).padding(.vertical, 4)
                .background(HexagonShape(cut: 0.5).fill(skin.color(\.page)))
                .overlay(HexagonShape(cut: 0.5).strokeBorder(skin.color(\.ink), lineWidth: 1.5))
        case .pixelBlock:
            Text(text).skinFont(.title(12))
                .foregroundStyle(skin.color(\.page))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Rectangle().fill(skin.extra(0, or: \.accent)).hardShadow(skin.color(\.accent), offset: 3))
        case .paperStrip:
            Text(text).skinFont(.title(11))
                .foregroundStyle(skin.color(\.accent))
                .padding(.horizontal, 13).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 4).fill(skin.color(\.card)).paperShadow())
                .overlay(StitchSeam(color: skin.color(\.accent), cornerRadius: 4, inset: 3, lineWidth: 1.2))
        case .highlighter:
            Text(text).skinFont(.title(13))
                .foregroundStyle(skin.color(\.ink))
                .padding(.horizontal, 6)
                .background {
                    GeometryReader { g in
                        Rectangle().fill(skin.color(\.accent))
                            .frame(width: g.size.width, height: g.size.height * 0.35)
                            .offset(y: g.size.height * 0.55)
                    }
                }
        }
    }
}

/// A filter chip. The visible chip is compact; its tap area is at least 44×44.
struct SkinChip: View {
    @Environment(\.skin) private var skin
    let text: String
    let selected: Bool
    let action: () -> Void
    init(_ text: String, selected: Bool, action: @escaping () -> Void) {
        self.text = text; self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            chip.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var chip: some View {
        switch skin.style.button {
        case .hex:
            Text(text).skinFont(.title(12))
                .foregroundStyle(selected ? skin.color(\.page) : skin.color(\.sub))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(HexagonShape().fill(selected ? skin.color(\.ink) : skin.color(\.page)))
                .overlay(HexagonShape().strokeBorder(selected ? skin.color(\.ink) : skin.color(\.dim), lineWidth: 2))
        case .pixelBlock:
            Text(text).skinFont(.title(13))
                .foregroundStyle(selected ? skin.color(\.page) : skin.color(\.sub))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Rectangle().fill(selected ? skin.extra(1, or: \.accent) : Color.clear).hardShadow(selected ? skin.extra(2, or: \.line) : .clear, offset: 3))
                .overlay(Rectangle().strokeBorder(selected ? Color.clear : skin.color(\.dim), lineWidth: 2))
        case .paperStitch:
            Text(text).skinFont(.title(12))
                .foregroundStyle(selected ? skin.color(\.card) : skin.color(\.sub))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? skin.extra(0, or: \.accent) : skin.color(\.card)).paperShadow())
                .overlay(StitchSeam(color: selected ? skin.color(\.card) : skin.color(\.dim), cornerRadius: 8, inset: 3, lineWidth: 1.2))
        case .sketchBox:
            let seed = SkinSeed.of(text)
            Text(text).skinFont(.title(13))
                .foregroundStyle(selected ? skin.color(\.ink) : skin.color(\.sub))
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(SketchBoxShape(seed: seed, wobble: 1.6).fill(selected ? skin.color(\.accent) : Color.clear))
                .overlay(SketchBoxShape(seed: seed, wobble: 1.6).stroke(selected ? skin.color(\.ink) : skin.color(\.dim), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)))
        }
    }
}

// MARK: - Search field

/// The search box: hexagon outline (black-gold), dark terminal block with a cyan frame and ">" prompt (pixel),
/// cream paper with a navy seam (stitch), wobbly ink box (sketch).
struct SkinSearchField: View {
    @Environment(\.skin) private var skin
    @Binding var text: String
    let prompt: String
    init(text: Binding<String>, prompt: String) { _text = text; self.prompt = prompt }

    private var isPixel: Bool { skin.style.button == .pixelBlock }

    private var field: some View {
        HStack(spacing: 10) {
            Group {
                if isPixel { Text(">").skinFont(.body(14)) } else { Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)) }
            }
            .foregroundStyle(skin.color(\.dim))
            .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(skin.color(\.dim)))
                .skinFont(.body(isPixel ? 14 : 13))
                .foregroundStyle(skin.color(\.ink))
                .tint(skin.color(\.accent))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .frame(minHeight: 44)
    }

    var body: some View {
        switch skin.style.button {
        case .hex:
            field.padding(.horizontal, 26).padding(.vertical, 2)
                .background(HexagonShape().fill(skin.color(\.page)))
                .overlay(HexagonShape().strokeBorder(skin.color(\.ink), lineWidth: 2))
        case .pixelBlock:
            field.padding(.horizontal, 16).padding(.vertical, 2)
                .background(Rectangle().fill(skin.extra(2, or: \.card)))
                .overlay(Rectangle().strokeBorder(skin.extra(1, or: \.accent), lineWidth: 3))
        case .paperStitch:
            field.padding(.horizontal, 18).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(skin.color(\.card)).paperShadow())
                .overlay(StitchSeam(color: skin.extra(0, or: \.ink), cornerRadius: 10, inset: 6, lineWidth: 2).allowsHitTesting(false))
        case .sketchBox:
            field.padding(.horizontal, 18).padding(.vertical, 2)
                .background(SketchBoxShape(seed: 21, wobble: 2).fill(skin.color(\.card)))
                .overlay(SketchBoxShape(seed: 21, wobble: 2).stroke(skin.color(\.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).allowsHitTesting(false))
        }
    }
}

// MARK: - Check circle

/// A quest's done mark: white disc with a dark tick (black-gold), yellow square (pixel), navy disc / dashed ring
/// (stitch), hand-drawn circle with a one-stroke tick (sketch). Undone is an empty outline.
struct SkinCheck: View {
    @Environment(\.skin) private var skin
    let done: Bool
    var size: CGFloat
    init(done: Bool, size: CGFloat = 20) { self.done = done; self.size = size }

    private var tickStyle: StrokeStyle { StrokeStyle(lineWidth: max(2, size * 0.15), lineCap: .round, lineJoin: .round) }

    var body: some View {
        mark
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(done ? "已完成" : "未完成")
    }

    @ViewBuilder private var mark: some View {
        switch skin.style.check {
        case .disc:
            if done {
                ZStack { Circle().fill(skin.color(\.ink)); TickShape().stroke(skin.color(\.page), style: tickStyle) }
            } else {
                Circle().strokeBorder(skin.color(\.dim), lineWidth: 2)
            }
        case .square:
            if done {
                ZStack { Rectangle().fill(skin.extra(0, or: \.accent)); TickShape().stroke(skin.color(\.page), style: tickStyle) }
            } else {
                Rectangle().strokeBorder(skin.color(\.dim), lineWidth: 2)
            }
        case .stitchDisc:
            if done {
                ZStack { Circle().fill(skin.extra(0, or: \.accent)); TickShape().stroke(skin.color(\.card), style: tickStyle) }
            } else {
                Circle().strokeBorder(skin.color(\.dim), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            }
        case .sketchCircle:
            ZStack {
                SketchCircleShape(seed: done ? 5 : 6).stroke(done ? skin.color(\.ink) : skin.color(\.dim), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if done { SketchTickShape().stroke(skin.color(\.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).padding(size * 0.12) }
            }
        }
    }
}

// MARK: - Stage

/// The hero object's backdrop: white disc in a gold ring (black-gold), cyan stepped frame (pixel), cream paper disc
/// with a red seam (stitch), nothing (sketch: the doodle stands on bare paper). `size` is the backdrop's diameter.
struct SkinStage<Content: View>: View {
    @Environment(\.skin) private var skin
    let size: CGFloat
    let content: Content
    init(size: CGFloat, @ViewBuilder content: () -> Content) { self.size = size; self.content = content() }

    var body: some View {
        ZStack {
            backdrop.accessibilityHidden(true)
            content
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var backdrop: some View {
        switch skin.style.stage {
        case .discRing:
            ZStack {
                Circle().fill(skin.color(\.accent))
                Circle().fill(skin.color(\.ink)).padding(size * 0.07)
            }
        case .pixelFrame:
            ZStack {
                SteppedFrameShape(step: 12).fill(skin.extra(1, or: \.accent))
                SteppedFrameShape(step: 12).fill(skin.color(\.card)).padding(18)
            }
        case .paperDisc:
            ZStack {
                Circle().fill(skin.color(\.card)).paperShadow(x: 3, y: 4)
                StitchSeam(color: skin.color(\.accent), cornerRadius: 0, inset: 11, lineWidth: 2.5, circle: true)
            }
        case .none:
            Color.clear
        }
    }
}

// MARK: - Background decoration

/// Which screen a decoration is drawn for: the lobby gets the full set, the splash most of it, other pages a hint.
enum DecorPage { case lobby, splash, other }

/// The page background's decoration, drawn in a 390×844 design space stretched to the view. Flat, behind content,
/// never tappable and hidden from VoiceOver.
struct SkinDecor: View {
    @Environment(\.skin) private var skin
    let page: DecorPage
    init(page: DecorPage) { self.page = page }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 390, y: size.height / 844)
            switch skin.style.decor {
            case .rays: rays(&context)
            case .pixelStars: pixelStars(&context)
            case .seams: seams(&context)
            case .doodles: doodles(&context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    /// Black-gold: flat light shards and crescents radiating from the hero; other pages keep two slivers top right.
    private func rays(_ context: inout GraphicsContext) {
        let ink = skin.color(\.ink), gold = skin.color(\.accent)
        guard page != .other else {
            context.fill(polygon([(250, 0), (300, 0), (274, 150)]), with: .color(gold))
            context.fill(polygon([(390, 40), (390, 70), (286, 150)]), with: .color(ink))
            return
        }
        context.fill(polygon([(172, 0), (214, 0), (193, 215)]), with: .color(ink))
        context.fill(polygon([(352, 0), (374, 0), (262, 232)]), with: .color(gold))
        context.fill(polygon([(0, 560), (98, 470), (0, 612)]), with: .color(gold))
        context.fill(polygon([(0, 372), (74, 377), (0, 381)]), with: .color(skin.extra(0, or: \.accent)))
        context.fill(polygon([(390, 424), (322, 431), (390, 436)]), with: .color(skin.extra(1, or: \.accent)))
        crescent(&context, outer: CGRect(x: 18, y: 205, width: 190, height: 190), cut: CGRect(x: 48, y: 190, width: 180, height: 180), color: ink)
        crescent(&context, outer: CGRect(x: 210, y: 245, width: 170, height: 170), cut: CGRect(x: 186, y: 230, width: 166, height: 166), color: ink)
    }

    private func crescent(_ context: inout GraphicsContext, outer: CGRect, cut: CGRect, color: Color) {
        context.drawLayer { layer in
            layer.fill(Path(ellipseIn: outer), with: .color(color))
            layer.blendMode = .destinationOut
            layer.fill(Path(ellipseIn: cut), with: .color(.black))
        }
    }

    /// Pixel: square stars everywhere; stepped hills along the bottom of the lobby.
    private func pixelStars(_ context: inout GraphicsContext) {
        let white = skin.color(\.ink), yellow = skin.extra(0, or: \.accent), pink = skin.color(\.accent), cyan = skin.extra(1, or: \.accent)
        let stars: [(CGFloat, CGFloat, CGFloat, Color)] = [(30, 120, 6, white), (340, 90, 8, yellow), (300, 170, 4, white), (60, 340, 4, pink),
                                                          (352, 400, 6, white), (130, 100, 4, cyan), (250, 70, 4, white)]
        for (x, y, w, c) in stars { context.fill(Path(CGRect(x: x, y: y, width: w, height: w)), with: .color(c)) }
        guard page == .lobby else { return }
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: 640))
        let steps: [(CGFloat, CGFloat)] = [(40, 0), (0, -20), (40, 0), (0, -20), (50, 0), (0, 20), (40, 0), (0, -40), (60, 0), (0, 40), (40, 0), (0, -20), (60, 0), (0, 20), (60, 0)]
        var point = CGPoint(x: 0, y: 640)
        for (dx, dy) in steps { point = CGPoint(x: point.x + dx, y: point.y + dy); hills.addLine(to: point) }
        hills.addLine(to: CGPoint(x: 390, y: 844)); hills.addLine(to: CGPoint(x: 0, y: 844)); hills.closeSubpath()
        context.fill(hills, with: .color(skin.extra(2, or: \.line).opacity(0.5)))
    }

    /// Stitch: the whole screen is a sheet sewn onto kraft paper; the lobby adds a few cross-stitches.
    private func seams(_ context: inout GraphicsContext) {
        let seam = Path(roundedRect: CGRect(x: 12, y: 12, width: 366, height: 820), cornerRadius: 22)
        context.stroke(seam, with: .color(skin.color(\.sub).opacity(0.55)), style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
        guard page != .other else { return }
        let colors = [skin.color(\.accent), skin.extra(0, or: \.ink), skin.extra(1, or: \.accent), skin.color(\.down)]
        let spots: [(CGFloat, CGFloat)] = [(52, 142), (340, 124), (350, 470), (40, 470)]
        for (i, spot) in spots.enumerated() {
            let (x, y) = spot
            var cross = Path()
            cross.move(to: CGPoint(x: x - 7, y: y - 7)); cross.addLine(to: CGPoint(x: x + 7, y: y + 7))
            cross.move(to: CGPoint(x: x + 7, y: y - 7)); cross.addLine(to: CGPoint(x: x - 7, y: y + 7))
            context.stroke(cross, with: .color(colors[i % colors.count]), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    /// Sketch: a few pen doodles (star, wave, circle, tick) on the lobby only; every other page stays blank paper.
    private func doodles(_ context: inout GraphicsContext) {
        guard page == .lobby else { return }
        let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(skin.color(\.ink))
        var star = Path()
        star.move(to: CGPoint(x: 300, y: 92))
        var p = CGPoint(x: 300, y: 92)
        for (dx, dy) in [(8, -14), (4, 16), (14, -6), (-10, 12), (12, 8), (-16, 0)] as [(CGFloat, CGFloat)] {
            p = CGPoint(x: p.x + dx, y: p.y + dy); star.addLine(to: p)
        }
        context.stroke(star, with: ink, style: style)
        var wave = Path()
        wave.move(to: CGPoint(x: 36, y: 150))
        wave.addQuadCurve(to: CGPoint(x: 58, y: 150), control: CGPoint(x: 46, y: 138))
        wave.addQuadCurve(to: CGPoint(x: 80, y: 150), control: CGPoint(x: 70, y: 162))
        context.stroke(wave, with: ink, style: style)
        context.stroke(SketchCircleShape(seed: 31).path(in: CGRect(x: 320, y: 470, width: 21, height: 21)), with: ink, style: style)
        var tick = Path()
        tick.move(to: CGPoint(x: 40, y: 520)); tick.addLine(to: CGPoint(x: 46, y: 526)); tick.addLine(to: CGPoint(x: 56, y: 514))
        context.stroke(tick, with: ink, style: style)
    }
}

// MARK: - Images and cards

/// One of the current skin's images. Always resizable and fitted: give it a frame.
struct SkinImage: View {
    @Environment(\.skin) private var skin
    private let name: String
    init(_ name: SkinArtName) { self.name = name.rawValue }
    /// Names outside `SkinArtName`, such as the vector skins' "digit_0"…"digit_9".
    init(named name: String) { self.name = name }
    var body: some View {
        Image(skin.art.image(named: name)).resizable().interpolation(.high).scaledToFit()
    }
}

/// A content card: rounded card colour (black-gold), square block with a hard shadow (pixel), paper with a seam
/// and paper shadow (stitch), plain white sheet (sketch).
struct SkinCard<Content: View>: View {
    @Environment(\.skin) private var skin
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let inner = content
            .foregroundStyle(skin.color(\.ink))
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        switch skin.style.button {
        case .hex:
            inner.background(RoundedRectangle(cornerRadius: 22).fill(skin.color(\.card)))
        case .pixelBlock:
            inner.background(Rectangle().fill(skin.color(\.card)).hardShadow(skin.extra(2, or: \.line)))
        case .paperStitch:
            inner.padding(4)
                .background(RoundedRectangle(cornerRadius: 16).fill(skin.color(\.card)).paperShadow())
                .overlay(StitchSeam(color: skin.color(\.dim), cornerRadius: 16, inset: 6, lineWidth: 1.5))
        case .sketchBox:
            inner.background(RoundedRectangle(cornerRadius: 22).fill(skin.color(\.card)))
        }
    }
}
