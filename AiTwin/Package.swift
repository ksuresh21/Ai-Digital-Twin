// swift-tools-version: 6.0
import PackageDescription

// AiTwin is a Swift Package that builds a macOS .app via Scripts/build-app.sh.
// See Docs/PACKAGING.md for why this is a package and not an .xcodeproj.
let package = Package(
    name: "AiTwin",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AiTwin", targets: ["AiTwinApp"]),
        .library(name: "AiTwinCore", targets: ["AiTwinCore"]),
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
        .target(name: "AiTwinCore", path: "Sources/AiTwinCore"),

        // Layer 2: platform seam. Protocols the domain needs the OS to satisfy.
        .target(name: "AiTwinPlatform", dependencies: ["AiTwinCore"], path: "Sources/AiTwinPlatform"),

        // Layer 3: macOS adapters. AppKit lives here and nowhere else.
        .target(name: "AiTwinMac", dependencies: ["AiTwinCore", "AiTwinPlatform"], path: "Sources/AiTwinMac"),

        // Layer 4: SwiftUI views.
        .target(name: "AiTwinUI", dependencies: ["AiTwinCore", "AiTwinMac"], path: "Sources/AiTwinUI"),

        // Layer 5: composition root.
        .executableTarget(
            name: "AiTwinApp",
            dependencies: ["AiTwinCore", "AiTwinPlatform", "AiTwinMac", "AiTwinUI"],
            path: "Sources/AiTwinApp"
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
