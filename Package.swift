// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoCleanerCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PhotoCleanerCore", targets: ["PhotoCleanerCore"])
    ],
    targets: [
        .target(name: "PhotoCleanerCore", path: "PhotoCleaner/Core"),
        .testTarget(
            name: "PhotoCleanerCoreTests",
            dependencies: ["PhotoCleanerCore"],
            path: "Tests/PhotoCleanerCoreTests"
        )
    ]
)
