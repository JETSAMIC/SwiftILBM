// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftILBM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftILBM",
            targets: ["SwiftILBM"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftILBM",
            path: "Sources/SwiftILBM"
        ),
        .testTarget(
            name: "SwiftILBMTests",
            dependencies: ["SwiftILBM"],
            path: "Tests/SwiftILBMTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
