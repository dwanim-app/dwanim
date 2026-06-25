// swift-tools-version: 5.10
import PackageDescription

// STRICT CONCURRENCY (M5 hardening).
//
// Every target compiles with `-strict-concurrency=complete` so the full set of
// data-race diagnostics is on. At tools-version 5.10 this stays in the Swift 5
// language MODE (diagnostics surface as warnings, not hard errors), which is the
// mechanism that works on this toolchain without bumping the manifest to 6.0.
// The package builds 0 warnings under it; the flag is therefore a free regression
// guard. Graduating to the Swift 6 language mode (`.swiftLanguageMode(.v6)`, races
// as ERRORS) requires tools-version 6.0 and is a separate, deliberate follow-up.
//
// Applied via a single shared array so a target can never silently drift off the
// flag (every `.target` / `.testTarget` / `.executableTarget` passes it).
let strictConcurrency: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"])
]

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
        .target(name: "SkinKit", swiftSettings: strictConcurrency),
        .testTarget(
            name: "SkinKitTests",
            dependencies: ["SkinKit"],
            swiftSettings: strictConcurrency
        ),
        .target(name: "PlayerCore", swiftSettings: strictConcurrency),
        .testTarget(
            name: "PlayerCoreTests",
            dependencies: ["PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "PlaybackKit",
            dependencies: ["PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "PlaybackKitTests",
            dependencies: ["PlaybackKit", "PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "SkinKitImageIO",
            dependencies: ["SkinKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "SkinKitImageIOTests",
            dependencies: ["SkinKitImageIO", "SkinKit"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "SkinRender",
            dependencies: ["SkinKit"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "SkinRenderTests",
            dependencies: ["SkinRender", "SkinKit"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "PlayerControl",
            dependencies: ["SkinRender", "PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "PlayerControlTests",
            dependencies: ["PlayerControl", "SkinRender", "PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .target(name: "SpectrumKit", swiftSettings: strictConcurrency),
        .testTarget(
            name: "SpectrumKitTests",
            dependencies: ["SpectrumKit"],
            swiftSettings: strictConcurrency
        ),
        .target(
            name: "DwanimUI",
            dependencies: ["PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "DwanimUITests",
            dependencies: ["DwanimUI", "PlayerCore"],
            swiftSettings: strictConcurrency
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
            ],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "SkinHarness",
            dependencies: [
                "SkinKit", "SkinKitImageIO", "SkinRender",
                "PlayerCore", "PlayerControl", "PlaybackKit", "SpectrumKit",
                "DwanimUI", "SkinAppKit"
            ],
            swiftSettings: strictConcurrency
        )
    ]
)
