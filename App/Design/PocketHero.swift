import SwiftUI
import RealityKit
import UIKit

/// Per-frame state shared between SwiftUI gestures and the RealityKit update loop.
@MainActor final class HeroMotion {
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
    @State private var root = Entity()
    @State private var numeral = Entity()
    @State private var pocketGroup = Entity()
    @State private var coin = Entity()
    @State private var built: (value: String, skin: String, pocket: Bool)?
    @State private var lastDrops = 0
    @State private var motion = HeroMotion()
    @State private var environment: EnvironmentResource?

    var body: some View {
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

            root.addChild(numeral)
            root.addChild(pocketGroup)
            content.add(root)
            if let environment = try? await Self.studioEnvironment() {
                root.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.4))
                root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
                self.environment = environment
            }
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                step(Float(event.deltaTime))
            }
        } update: { _ in
            rebuildIfNeeded()
            if drops != lastDrops {
                let fresh = drops > lastDrops
                lastDrops = drops
                if fresh { dropCoin() }
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { motion.tilt = CGSize(width: $0.translation.width / 160, height: $0.translation.height / 220) }
            .onEnded { _ in motion.tilt = .zero })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Building

    private func rebuildIfNeeded() {
        guard built?.value != value || built?.skin != skin.id || built?.pocket != showsPocket else { return }
        let firstBuild = built == nil
        built = (value, skin.id, showsPocket)
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
        // Fit wide values (e.g. "−0.02%") into the same frame as two digits.
        let fit = Float(min(1, 3.6 / max(layout.width, 0.1)))
        numeral.scale = [fit, fit, fit]
        if !firstBuild && !reduceMotion { pop() }

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
            coin = Self.coin(metal)
            coin.position = [0, 1.55, -0.12]
            pocketGroup.addChild(coin)
            pocketGroup.position.y = 1.75
            numeral.position.y = -1.75
            root.scale = [0.82, 0.82, 0.82]
            root.position.y = -0.45
        } else {
            numeral.position.y = 0
            root.scale = [1, 1, 1]
            root.position.y = 0
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
        motion.time += dt
        let target = SIMD2<Float>(Float(motion.tilt.width), Float(motion.tilt.height))
        motion.smoothed += (target - motion.smoothed) * min(1, dt * 6)
        let sway: Float = reduceMotion ? 0 : sin(motion.time * 0.5) * 0.12
        root.orientation = simd_quatf(angle: sway + motion.smoothed.x * 0.45, axis: [0, 1, 0]) * simd_quatf(angle: motion.smoothed.y * 0.25, axis: [1, 0, 0])
        if showsPocket, motion.spinning, !reduceMotion {
            coin.orientation = simd_quatf(angle: motion.time * 1.5, axis: [0, 1, 0])
            coin.position.y = 1.55 + sin(motion.time * 2) * 0.08
        }
        if motion.shake > 0 {
            motion.shake = max(0, motion.shake - dt)
            let a = motion.shake * 0.5
            root.position.x = Float.random(in: -a...a) * 0.3
        } else { root.position.x = 0 }
    }

    private func pop() {
        numeral.scale *= 1.25
        let settled = Transform(scale: numeral.scale / 1.25, rotation: numeral.orientation, translation: numeral.position)
        numeral.move(to: settled, relativeTo: numeral.parent, duration: 0.45, timingFunction: .easeOut)
    }

    private func dropCoin() {
        guard showsPocket else { onLanded(); return }
        if reduceMotion { onLanded(); return }
        motion.spinning = false
        coin.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        var inside = coin.transform; inside.translation.y = -0.35
        coin.move(to: inside, relativeTo: pocketGroup, duration: 0.5, timingFunction: .easeIn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            motion.shake = 0.38
            onLanded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            coin.position = [0, 6.5, -0.12]
            var hover = coin.transform; hover.translation.y = 1.55
            coin.move(to: hover, relativeTo: pocketGroup, duration: 0.7, timingFunction: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { motion.spinning = true }
        }
    }
}
