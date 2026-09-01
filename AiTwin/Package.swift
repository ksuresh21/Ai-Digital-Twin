// swift-tools-version: 6.0
import PackageDescription

// AiTwin is a Swift Package that builds a macOS .app via Scripts/build-app.sh.
// See Docs/PACKAGING.md for why this is a package and not an .xcodeproj.
// Developer tooling -- the mood previews, the dummy-data generator -- is
// compiled ONLY into debug builds. A release build cannot contain it: the code
// is not merely hidden behind a toggle, it is absent from the binary. That is
// what makes `./Scripts/build-app.sh` safe to hand to someone.
let devOnly = SwiftSetting.define("AITWIN_DEV", .when(configuration: .debug))

let package = Package(
    name: "AiTwin",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AiTwin", targets: ["AiTwinApp"]),
        .library(name: "AiTwinCore", targets: ["AiTwinCore"]),
        .library(name: "AiTwinMac", targets: ["AiTwinMac"]),
    ],
    dependencies: [
        // TEST-ONLY dependency. swift-testing normally ships inside Xcode; this
        // machine has Command Line Tools only, so we vendor it to keep `swift test`
        // working. Once Xcode is installed, delete this dependency and the
        // .product(...) line below -- the test source needs no other change.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        // Layer 1: pure domain. Foundation only -- no AppKit, no SwiftUI.
        // This is the module a future Windows port reuses verbatim.
        .target(name: "AiTwinCore", path: "Sources/AiTwinCore", swiftSettings: [devOnly]),

        // Layer 2: platform seam. Protocols the domain needs the OS to satisfy.
        .target(name: "AiTwinPlatform", dependencies: ["AiTwinCore"], path: "Sources/AiTwinPlatform",
                swiftSettings: [devOnly]),

        // Layer 3: macOS adapters. AppKit lives here and nowhere else.
        .target(name: "AiTwinMac", dependencies: ["AiTwinCore", "AiTwinPlatform"], path: "Sources/AiTwinMac",
                swiftSettings: [devOnly]),

        // Layer 4: SwiftUI views.
        .target(name: "AiTwinUI", dependencies: ["AiTwinCore", "AiTwinMac"], path: "Sources/AiTwinUI",
                swiftSettings: [devOnly]),

        // Layer 5: composition root.
        .executableTarget(
            name: "AiTwinApp",
            dependencies: ["AiTwinCore", "AiTwinPlatform", "AiTwinMac", "AiTwinUI"],
            path: "Sources/AiTwinApp",
            swiftSettings: [devOnly]
        ),

        // Window movement can only be verified against a real window, so this
        // target exists solely for the handful of behaviours that cannot be
        // proven in Core.
        .testTarget(
            name: "AiTwinMacTests",
            dependencies: [
                "AiTwinCore",
                "AiTwinMac",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/AiTwinMacTests"
        ),

        .testTarget(
            name: "AiTwinCoreTests",
            dependencies: [
                "AiTwinCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/AiTwinCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
