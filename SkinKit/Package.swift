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
        .library(name: "PlayerControl", targets: ["PlayerControl"]),
        .library(name: "PlaybackKit", targets: ["PlaybackKit"]),
        .library(name: "SpectrumKit", targets: ["SpectrumKit"]),
        .library(name: "DwanimUI", targets: ["DwanimUI"]),
        .library(name: "SkinAppKit", targets: ["SkinAppKit"])
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
        .target(name: "PlayerControl", dependencies: ["SkinRender", "PlayerCore"]),
        .testTarget(
            name: "PlayerControlTests",
            dependencies: ["PlayerControl", "SkinRender", "PlayerCore"]
        ),
        .target(name: "SpectrumKit"),
        .testTarget(name: "SpectrumKitTests", dependencies: ["SpectrumKit"]),
        .target(name: "DwanimUI", dependencies: ["PlayerCore"]),
        .testTarget(
            name: "DwanimUITests",
            dependencies: ["DwanimUI", "PlayerCore"]
        ),
        // The reusable AppKit tier (same platform tier as the harness: AppKit is
        // allowed here). Holds the window-controller base, the shared scaled
        // mouse/scroll-forwarding view, the region-mask layer, the CGImage
        // bridge, and the redraw-loop/tap wiring.
        .target(
            name: "SkinAppKit",
            dependencies: [
                "SkinKit", "SkinRender", "PlayerCore",
                "PlayerControl", "SpectrumKit"
            ]
        ),
        .executableTarget(
            name: "SkinHarness",
            dependencies: [
                "SkinKit", "SkinKitImageIO", "SkinRender",
                "PlayerCore", "PlayerControl", "PlaybackKit", "SpectrumKit",
                "DwanimUI", "SkinAppKit"
            ]
        )
    ]
)
