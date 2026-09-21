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
    // LOCALIZATION FOUNDATION (l10n step). Declaring the package's source
    // (development) language is the SwiftPM prerequisite for `Bundle.module`
    // localization: without it a target with localized resources has no notion
    // of a fallback locale, and `String(localized:bundle:)` / `NSLocalizedString`
    // resolution against `Bundle.module` is undefined. Tools-version 5.10 already
    // supports this key, so no manifest bump is needed.
    defaultLocalization: "en",
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
        .library(name: "DwanimItUI", targets: ["DwanimItUI"]),
        .library(name: "SkinAppKit", targets: ["SkinAppKit"])
    ],
    targets: [
        // TEST-SUPPORT ONLY — deliberately NOT a product, and deliberately
        // pathed under Tests/ so nothing in the shipping `Sources/` tier can
        // reach it. It holds the single seam every in-process click harness
        // takes its activation precondition from (`GUIFocusHarness`), shared by
        // two test targets (DwanimItUITests and PlaybackKitTests) which is why
        // it has to be a module rather than a file in either of them.
        .target(
            name: "GUIFocusHarness",
            path: "Tests/GUIFocusHarness",
            swiftSettings: strictConcurrency
        ),
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
        // `DwanimItUI` is a TEST-ONLY dependency here, for the end-to-end
        // click-through test that drives the REAL `CadenceTransport` buttons over a
        // REAL multi-format queue on the REAL `AVAudioEnginePlayer`
        // (`RealQueueTransportClickThroughTests`). It lives in this target rather
        // than in `DwanimItUITests` because what it proves is a PLAYBACK property —
        // that every manual ▶▶ / ◀◀ step across a 44.1k<->48k and mono<->stereo
        // boundary really plays — so it belongs beside
        // `AVAudioEnginePlayerFormatChangeTests` and reuses this target's
        // `AudioOutputDeviceProbe` device guard rather than duplicating it.
        // The PRODUCT graph is untouched: `DwanimItUI` still depends only on
        // `PlayerCore`, and `PlaybackKit` does not depend on `DwanimItUI`.
        .testTarget(
            name: "PlaybackKitTests",
            dependencies: ["PlaybackKit", "PlayerCore", "DwanimItUI", "GUIFocusHarness"],
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
            name: "DwanimItUI",
            dependencies: ["PlayerCore"],
            // The in-window emblem renders the SAME bitmap as the app icon
            // (a copy of the committed icon_256x256.png) so the glass-panel mark
            // matches the dock/Finder icon exactly. It lives in an ASSET CATALOG
            // — Resources/EmblemAssets.xcassets/dwennimmen-emblem.imageset — so
            // SwiftUI's `Image("dwennimmen-emblem", bundle: .module)` resolves it
            // (Image(name:bundle:) looks up compiled asset-catalog names, NOT
            // loose files; a loose PNG never resolves and renders blank). `.process`
            // runs the resource pipeline, which compiles the .xcassets into an
            // Assets.car inside `Bundle.module`. The emblem is a bundled asset, NOT
            // an import: DwanimItUI still imports only SwiftUI + PlayerCore (no AppKit).
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "DwanimItUITests",
            dependencies: ["DwanimItUI", "PlayerCore", "GUIFocusHarness"],
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
            // LOCALIZATION FOUNDATION (l10n step). SkinAppKit ships ~13
            // user-visible strings but had no resource bundle, so it had no
            // `Bundle.module` to resolve a String Catalog against. Adding a
            // `.process("Resources")` rule makes SwiftPM synthesize a
            // `Bundle.module` for the target and pick up any catalog placed in
            // `Sources/SkinAppKit/Resources/`. The catalog is seeded here (empty
            // strings map) so the mechanism is ready; the 13 call-site
            // conversions are a later step.
            resources: [.process("Resources")],
            swiftSettings: strictConcurrency
        ),
        // In-process AppKit tests for the shaped-window seam: they build a REAL
        // NSWindow + ScaledImageView through the production `showInteractiveWindow`
        // path and drive SYNTHESIZED NSEvents (no mouse / accessibility permission,
        // no CGEvent posting), so the two owner-unverifiable interactive behaviours
        // — shaped-window title-bar drag, and cut-out hit-test / click-through
        // preconditions — become deterministic. Depends on PlayerCore too because
        // the real window path takes a `PlayerCore` (driven by an in-memory fake
        // engine here — no audio framework is touched).
        .testTarget(
            name: "SkinAppKitTests",
            dependencies: ["SkinAppKit", "SkinKit", "SkinRender", "PlayerCore"],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "SkinHarness",
            dependencies: [
                "SkinKit", "SkinKitImageIO", "SkinRender",
                "PlayerCore", "PlayerControl", "PlaybackKit", "SpectrumKit",
                "DwanimItUI", "SkinAppKit"
            ],
            swiftSettings: strictConcurrency
        )
    ]
)
