// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Framelet",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Framelet", targets: ["Framelet"])],
    targets: [
        .target(name: "FrameletCore"),
        .target(name: "CaptureTextRenderer", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
        .executableTarget(name: "Framelet", dependencies: ["FrameletCore", "CaptureTextRenderer"]),
        .executableTarget(name: "FrameletChecks", dependencies: ["FrameletCore"], path: "Tests/FrameletCoreTests", resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
