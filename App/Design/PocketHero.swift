import SwiftUI
import RealityKit
import UIKit

/// Everything the RealityKit scene keeps between SwiftUI updates. A reference type, because writing @State while
/// SwiftUI is updating the view is ignored: counters kept there re-triggered the coin drop on every update.
@MainActor final class HeroScene {
    let root = Entity(), numeral = Entity(), pocketGroup = Entity()
    var coin = Entity()
    var builtKey: String?
    var handledDrops: Int?
    var numeralWidth: Float = 1
    var aspect: Float = 0.6
    var showsPocket = false
    var reduceMotion = false
    var tilt: CGSize = .zero
    var smoothed: SIMD2<Float> = .zero
    var time: Float = 0
    var spinning = true
    var shake: Float = 0
}

/// The 3D hero of a screen, built like the concept page: a numeral made of matte and polished blocks, optionally a
/// stitched pocket with a hovering coin above it. Increasing `drops` plays the coin falling into the pocket.
struct PocketHero: View {
    var value: String
    var showsPocket: Bool
    var skin: Skin
    var drops: Int
    var label: String
    /// Called when the coin passes the lip: the caller updates its numbers, plays the burst, sound and haptics.
    var onLanded: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = HeroScene()
    private var root: Entity { scene.root }
    private var numeral: Entity { scene.numeral }
    private var pocketGroup: Entity { scene.pocketGroup }

    var body: some View {
        GeometryReader { geo in
        RealityView { content in
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 28
            camera.position = [0, 0, 16]
            content.add(camera)

            let light = DirectionalLight()
            light.light.intensity = 2600
            light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 30, depthBias: 2)
            light.look(at: .zero, from: [-4, 6, 9], relativeTo: nil)
            content.add(light)
            let fill = DirectionalLight()
            fill.light.intensity = 1300
            fill.look(at: .zero, from: [5, 1, 10], relativeTo: nil)
            content.add(fill)

            root.addChild(numeral)
            root.addChild(pocketGroup)
            content.add(root)
            if let environment = try? await Self.studioEnvironment() {
                root.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 1))
                root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
            }
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                step(Float(event.deltaTime))
            }
        } update: { _ in
            scene.reduceMotion = reduceMotion
            scene.aspect = Float(max(geo.size.width, 1) / max(geo.size.height, 1))
            rebuildIfNeeded()
            fit()
            // The first update only records the count: opening a screen never plays a drop.
            if let handled = scene.handledDrops, drops > handled { scene.handledDrops = drops; dropCoin() }
            else if scene.handledDrops == nil { scene.handledDrops = drops }
        }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { scene.tilt = CGSize(width: $0.translation.width / 160, height: $0.translation.height / 220) }
            .onEnded { _ in scene.tilt = .zero })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Building

    private func rebuildIfNeeded() {
        let key = "\(value)|\(skin.id)|\(showsPocket)"
        guard scene.builtKey != key else { return }
        let firstBuild = scene.builtKey == nil
        let valueChanged = scene.builtKey.map { !$0.hasPrefix(value + "|") } ?? false
        scene.builtKey = key
        scene.showsPocket = showsPocket
        let matte = Self.material(skin.matte, metalness: 0, roughness: 0.85)
        let metal = Self.material(skin.metal.color, metalness: skin.metal.metalness, roughness: skin.metal.roughness)

        numeral.children.removeAll()
        let layout = BlockGlyphs.layout(value)
        for block in layout.blocks {
            let mesh: MeshResource
            switch block.shape {
            case .box, .slash:
                mesh = .generateBox(width: Float(block.width), height: Float(block.height), depth: Float(block.depth), cornerRadius: Float(min(BlockGlyphs.radius, block.width / 2.1)))
            case .ring:
                mesh = Self.ringMesh(radius: BlockGlyphs.ringRadius, tube: 0.1, depth: block.depth)
            }
            let entity = ModelEntity(mesh: mesh, materials: [block.gold ? metal : matte])
            entity.position = [Float(block.x), Float(block.y), block.gold ? 0.03 : 0]
            entity.orientation = simd_quatf(angle: Float(block.rotation), axis: [0, 0, 1])
            entity.components.set(GroundingShadowComponent(castsShadow: true))
            numeral.addChild(entity)
        }
        scene.numeralWidth = Float(max(layout.width, 0.1))
        if !firstBuild && valueChanged && !reduceMotion { pop() }

        pocketGroup.children.removeAll()
        pocketGroup.isEnabled = showsPocket
        if showsPocket {
            let back = ModelEntity(mesh: Self.extruded(PocketShape.back(), depth: 0.16), materials: [Self.material(skin.matte2, metalness: 0, roughness: 0.9)])
            back.position.z = -0.48
            let front = ModelEntity(mesh: Self.extruded(PocketShape.front(), depth: 0.3), materials: [matte])
            front.position.z = 0.2
            pocketGroup.addChild(back); pocketGroup.addChild(front)
            for stitch in PocketShape.stitches() {
                let s = ModelEntity(mesh: .generateBox(width: 0.06, height: Float(stitch.length * 0.85), depth: 0.06, cornerRadius: 0.03), materials: [metal])
                s.position = [Float(stitch.center.x), Float(stitch.center.y), 0.53]
                s.orientation = simd_quatf(angle: Float(stitch.angle) - .pi / 2, axis: [0, 0, 1])
                pocketGroup.addChild(s)
            }
            scene.coin = Self.coin(metal)
            scene.coin.position = [0, 1.55, -0.12]
            pocketGroup.addChild(scene.coin)
            pocketGroup.position.y = 1.75
            numeral.position.y = -1.75
        } else {
            numeral.position.y = 0
        }
    }

    /// Scales the scene to its frame: the pocket screen fills the height, a lone numeral 82% of the width.
    private func fit() {
        let visibleHeight: Float = 2 * 16 * tan(14 * .pi / 180), visibleWidth = visibleHeight * scene.aspect
        if showsPocket {
            // Content spans y −2.75 (numeral bottom) to 3.9 (coin top): 6.65 high, centred at 0.575.
            let s = min(0.92 * visibleHeight / 6.65, 0.85 * visibleWidth / max(2.7, scene.numeralWidth))
            root.scale = [s, s, s]; root.position.y = -0.575 * s
        } else {
            let s = min(0.82 * visibleWidth / scene.numeralWidth, 0.8 * visibleHeight / 2.2)
            root.scale = [s, s, s]; root.position.y = 0
        }
    }

    private static func material(_ rgb: UInt32, metalness: Double, roughness: Double) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1))
        m.metallic = .init(floatLiteral: Float(metalness))
        m.roughness = .init(floatLiteral: Float(roughness))
        return m
    }

    private static func extruded(_ outline: [SIMD2<Double>], depth: Double) -> MeshResource {
        var path = Path()
        path.move(to: CGPoint(x: outline[0].x, y: outline[0].y))
        for p in outline.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        path.closeSubpath()
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: Float(depth))
        options.chamferRadius = 0.06
        return (try? MeshResource(extruding: path, extrusionOptions: options)) ?? .generateBox(size: 0.01)
    }

    private static func ringMesh(radius: Double, tube: Double, depth: Double) -> MeshResource {
        var path = Path()
        path.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        let inner = radius - tube * 2
        path.addEllipse(in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: Float(depth))
        options.chamferRadius = 0.04
        return (try? MeshResource(extruding: path.normalized(eoFill: true), extrusionOptions: options)) ?? .generateSphere(radius: Float(radius))
    }

    private static func coin(_ metal: PhysicallyBasedMaterial) -> Entity {
        let coin = Entity()
        let body = ModelEntity(mesh: .generateCylinder(height: 0.17, radius: 0.6), materials: [metal])
        body.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let boss = ModelEntity(mesh: .generateCylinder(height: 0.22, radius: 0.3), materials: [metal])
        boss.orientation = body.orientation
        coin.addChild(body); coin.addChild(boss)
        return coin
    }

    /// A soft studio: a bright top, two light boxes and a dark floor, so polished metal has something to reflect.
    private static func studioEnvironment() async throws -> EnvironmentResource {
        let width = 256, height = 128
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let colors = [UIColor(white: 0.95, alpha: 1).cgColor, UIColor(white: 0.55, alpha: 1).cgColor, UIColor(white: 0.08, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 40, y: 80, width: 50, height: 22)); context.fill(CGRect(x: 160, y: 86, width: 40, height: 16))
        return try await EnvironmentResource(equirectangular: context.makeImage()!)
    }

    // MARK: Motion

    private func step(_ dt: Float) {
        scene.time += dt
        let target = SIMD2<Float>(Float(scene.tilt.width), Float(scene.tilt.height))
        scene.smoothed += (target - scene.smoothed) * min(1, dt * 6)
        let sway: Float = scene.reduceMotion ? 0 : sin(scene.time * 0.5) * 0.12
        root.orientation = simd_quatf(angle: sway + scene.smoothed.x * 0.45, axis: [0, 1, 0]) * simd_quatf(angle: scene.smoothed.y * 0.25, axis: [1, 0, 0])
        if scene.showsPocket, scene.spinning, !scene.reduceMotion {
            scene.coin.orientation = simd_quatf(angle: scene.time * 1.5, axis: [0, 1, 0])
            scene.coin.position.y = 1.55 + sin(scene.time * 2) * 0.08
        }
        if scene.shake > 0 {
            scene.shake = max(0, scene.shake - dt)
            let a = scene.shake * 0.5
            root.position.x = Float.random(in: -a...a) * 0.3
        } else { root.position.x = 0 }
    }

    private func pop() {
        numeral.scale = [1.25, 1.25, 1.25]
        let settled = Transform(scale: [1, 1, 1], rotation: numeral.orientation, translation: numeral.position)
        numeral.move(to: settled, relativeTo: numeral.parent, duration: 0.45, timingFunction: .easeOut)
    }

    private func dropCoin() {
        guard showsPocket else { onLanded(); return }
        // Reduced motion, or a tap while a coin is still falling: count it without another animation.
        if reduceMotion || !scene.spinning { onLanded(); return }
        scene.spinning = false
        scene.coin.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        var inside = scene.coin.transform; inside.translation.y = -0.35
        scene.coin.move(to: inside, relativeTo: pocketGroup, duration: 0.5, timingFunction: .easeIn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            scene.shake = 0.38
            onLanded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            scene.coin.position = [0, 6.5, -0.12]
            var hover = scene.coin.transform; hover.translation.y = 1.55
            scene.coin.move(to: hover, relativeTo: pocketGroup, duration: 0.7, timingFunction: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { scene.spinning = true }
        }
    }
}
