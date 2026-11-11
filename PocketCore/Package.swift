// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "PocketCore", targets: ["PocketCore"])],
    targets: [
        .target(name: "PocketCore", resources: [.process("Resources")]),
        .testTarget(name: "PocketCoreTests", dependencies: ["PocketCore"])
    ],
    swiftLanguageModes: [.v5]
)
