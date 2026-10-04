// swift-tools-version: 5.9
import PackageDescription

// Training analysis shared by torque and suit: soreness attribution now,
// torque-coverage profiles later (TORQUE_COVERAGE_PLAN.md). Foundation only.
let package = Package(
    name: "BiomechKit",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "BiomechKit", targets: ["BiomechKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sphericalwave/AnatomyKit.git", branch: "main"),
    ],
    targets: [
        .target(name: "BiomechKit", dependencies: ["AnatomyKit"]),
        .testTarget(name: "BiomechKitTests", dependencies: ["BiomechKit"]),
    ]
)
