// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SkinKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SkinKit", targets: ["SkinKit"]),
        .library(name: "SkinKitImageIO", targets: ["SkinKitImageIO"]),
        .library(name: "SkinRender", targets: ["SkinRender"]),
        .library(name: "PlayerCore", targets: ["PlayerCore"]),
        .library(name: "PlaybackKit", targets: ["PlaybackKit"])
    ],
    targets: [
        .target(name: "SkinKit"),
        .testTarget(name: "SkinKitTests", dependencies: ["SkinKit"]),
        .target(name: "PlayerCore"),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"]),
        .target(name: "PlaybackKit", dependencies: ["PlayerCore"]),
        .testTarget(
            name: "PlaybackKitTests",
            dependencies: ["PlaybackKit", "PlayerCore"]
        ),
        .target(name: "SkinKitImageIO", dependencies: ["SkinKit"]),
        .testTarget(
            name: "SkinKitImageIOTests",
            dependencies: ["SkinKitImageIO", "SkinKit"]
        ),
        .target(name: "SkinRender", dependencies: ["SkinKit"]),
        .testTarget(
            name: "SkinRenderTests",
            dependencies: ["SkinRender", "SkinKit"]
        ),
        .executableTarget(
            name: "SkinHarness",
            dependencies: ["SkinKit", "SkinKitImageIO", "SkinRender", "PlayerCore", "PlaybackKit"]
        )
    ]
)
