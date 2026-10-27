// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Framelet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Framelet", targets: ["Framelet"])],
    targets: [
        .target(name: "FrameletCore"),
        .executableTarget(name: "Framelet", dependencies: ["FrameletCore"]),
        .executableTarget(name: "FrameletChecks", dependencies: ["FrameletCore"], path: "Tests/FrameletCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
