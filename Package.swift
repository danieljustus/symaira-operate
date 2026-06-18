// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "symaira-operate",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "SymOperateCore", targets: ["SymOperateCore"]),
        .library(name: "SymOperateMCP", targets: ["SymOperateMCP"]),
        .executable(name: "symoperate", targets: ["symoperate"]),
    ],
    targets: [
        .target(
            name: "SymOperateCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .target(
            name: "SymOperateMCP",
            dependencies: ["SymOperateCore"]
        ),
        .executableTarget(
            name: "symoperate",
            dependencies: ["SymOperateCore", "SymOperateMCP"]
        ),
        .testTarget(
            name: "SymOperateCoreTests",
            dependencies: ["SymOperateCore", "SymOperateMCP"]
        ),
        .testTarget(
            name: "SymOperateSmokeTests",
            dependencies: ["SymOperateCore", "SymOperateMCP"]
        ),
    ],
    // v0.1 ships in Swift 5 language mode; tightening to Swift 6 strict
    // concurrency (AppKit/ScreenCaptureKit MainActor isolation) is tracked in
    // docs/roadmap.md.
    swiftLanguageModes: [.v5]
)
