// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SkinKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SkinKit", targets: ["SkinKit"]),
        .library(name: "SkinKitImageIO", targets: ["SkinKitImageIO"])
    ],
    targets: [
        .target(name: "SkinKit"),
        .testTarget(name: "SkinKitTests", dependencies: ["SkinKit"]),
        .target(name: "SkinKitImageIO", dependencies: ["SkinKit"]),
        .testTarget(
            name: "SkinKitImageIOTests",
            dependencies: ["SkinKitImageIO", "SkinKit"]
        ),
        .executableTarget(
            name: "SkinHarness",
            dependencies: ["SkinKit", "SkinKitImageIO"]
        )
    ]
)
