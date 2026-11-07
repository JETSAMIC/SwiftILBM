// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftILBM",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SwiftILBM", targets: ["SwiftILBM"])
    ],
    targets: [
        .target(name: "SwiftILBM"),
        .testTarget(name: "SwiftILBMTests", dependencies: ["SwiftILBM"])
    ],
    swiftLanguageModes: [.v6]
)
