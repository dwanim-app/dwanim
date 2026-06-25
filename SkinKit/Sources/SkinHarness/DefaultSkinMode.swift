import AppKit
import DwanimUI
import Foundation
import PlaybackKit
import PlayerCore
import SkinAppKit
import SpectrumKit
import SwiftUI

// SkinHarness default-skin mode: the app's OWN face when no `.wsz` is loaded —
// the Liquid Glass dock-bar player (`DwanimUI.DwanimPlayerScene`) hosted in an
// NSWindow, wired to a live `PlayerCore` + `AVAudioEnginePlayer`.
//
// Usage:
//   SkinHarness --default-skin <audiofile> [<audiofile>...] [--scale N]
//
// Flow (mirrors --interactive's engine/tap/analyzer wiring, but the view is
// SwiftUI instead of a composed bitmap):
//   1. Build a PlayerCore over AVAudioEnginePlayer; load the audio files as a
//      playlist (Track.title = file-name stem — the user's own file).
//   2. Build a DwanimUI.PlayerViewModel for the live clock + spectrum levels.
//   3. Host `DwanimPlayerScene(core:model:)` in an NSHostingView inside an
//      NSWindow. The scene already paints the colourful backdrop behind the
//      glass, so the materials have something to blur.
//   4. Install the engine's PCM tap -> SpectrumAnalyzer (main thread) -> model.levels.
//   5. A ~22 Hz main-thread timer copies the engine clock into the model and
//      runs the analyzer on the latest stashed samples.
//
// The ONLY text shown is the live track title (or the quiet "Dwanim" the view
// falls back to) — no brand names.

// MARK: - Argument parsing

/// Parsed default-skin arguments: one-or-more audio files and the window scale.
private struct DefaultSkinArguments {
    var audioPaths: [String]
    var scale: Int
}

private let defaultSkinUsage =
    "Usage: SkinHarness --default-skin <audiofile> [<audiofile>...] [--scale N]"

/// Parse the default-skin argument vector. `--default-skin` and everything after
/// it is consumed here; positionals are audio files and `--scale N` may appear
/// anywhere after the flag.
private func parseDefaultSkinArguments(_ argv: [String]) -> DefaultSkinArguments {
    guard let flagIndex = argv.firstIndex(of: "--default-skin") else {
        defaultSkinFail("Internal: --default-skin dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 1

    var index = flagIndex + 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...8).contains(value) else {
                defaultSkinFail("--scale requires an integer in 1...8. \(defaultSkinUsage)")
            }
            scale = value
            index += 2
        default:
            positionals.append(arg)
            index += 1
        }
    }

    guard !positionals.isEmpty else {
        defaultSkinFail("Missing required audio file(s). \(defaultSkinUsage)")
    }
    return DefaultSkinArguments(audioPaths: positionals, scale: scale)
}

// MARK: - Controller

/// Owns the live default-skin window: the core, the view-model, the hosting
/// view, the audio tap, and the ~22 Hz clock/spectrum timer. The SwiftUI view
/// observes `core` + `model`; this controller only feeds the model (clock +
/// levels) and tears down on close.
@MainActor
private final class DefaultSkinController: SkinWindowController {
    private let core: PlayerCore
    private let model: PlayerViewModel
    private let analyzer: SpectrumAnalyzer
    private let latestSamples = SpectrumFeed()

    /// The shared redraw cadence + audio-tap wiring (timer + tap install / remove
    /// + the `SpectrumFeed` write). Built in `init`, started by `start()`, stopped
    /// by `tearDown()`.
    private var redrawLoop: RedrawLoop?

    /// Number of spectrum bars in the default-skin row. A small fixed count
    /// reads well in the compact bar (the SwiftUI row lays them out to fit);
    /// unlike the bitmap skin, width here is flexible so it need not be derived.
    private static let barCount = 24

    init(core: PlayerCore, model: PlayerViewModel, tap: AudioTapProviding?) {
        self.core = core
        self.model = model
        self.analyzer = SpectrumAnalyzer(barCount: DefaultSkinController.barCount)
        super.init()

        // ~22 Hz: smooth enough for the spectrum and progress without burning the
        // main thread. The per-tick work is `@MainActor`; the shared loop fires it
        // on the main run loop, so `assumeIsolated` is sound (same pattern the
        // controller used before the lift).
        redrawLoop = RedrawLoop(
            interval: 0.045,
            tap: tap,
            feed: latestSamples
        ) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Install the PCM tap and start the main-thread timer that copies the engine
    /// clock into the model and runs the analyzer (both via the shared loop).
    func start() {
        redrawLoop?.start()
    }

    // MARK: One tick

    /// Copy the live engine clock into the model and push fresh spectrum levels.
    /// All of this is on the main thread, so the `@MainActor` `PlayerViewModel`
    /// mutations are safe and SwiftUI re-renders from the observable changes.
    private func tick() {
        model.updateClock(currentTime: core.currentTime, duration: core.duration)
        let snapshot = latestSamples.latest()
        model.levels = analyzer.process(snapshot.samples, sampleRate: snapshot.sampleRate)
    }

    // MARK: Teardown

    /// The window is closing — stop the redraw loop (invalidate the timer + remove
    /// the tap) before the base terminates the app.
    nonisolated override func tearDown() {
        // `redrawLoop?.stop()` only touches the loop's own (Sendable) state; hop
        // is unnecessary, but the property is main-actor-isolated, so read it
        // through an assumeIsolated to match the controller's isolation.
        MainActor.assumeIsolated {
            redrawLoop?.stop()
        }
    }
}

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var liveDefaultSkinController: DefaultSkinController?

// MARK: - Entry point

/// Run the default-skin mode and never return: build the core + view-model, host
/// the SwiftUI scene, start the clock/spectrum timer, and drive the run loop.
@MainActor
func runDefaultSkinMode() -> Never {
    let arguments = parseDefaultSkinArguments(CommandLine.arguments)

    // Build the core and load the audio files. Each Track.title is the file's own
    // name stem (the user's file — fine to display); NO brand title is invented.
    let tracks = arguments.audioPaths.map { path -> Track in
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        return Track(url: url, title: stem)
    }
    let engine = AVAudioEnginePlayer()
    let core = PlayerCore(engine: engine)
    core.load(tracks)

    let model = PlayerViewModel()

    openDefaultSkinWindow(core: core, model: model, tap: engine, scale: arguments.scale)
}

/// Build and show the default-skin window hosting `DwanimPlayerScene`, then start
/// the timer and run the app. Never returns.
@MainActor
private func openDefaultSkinWindow(
    core: PlayerCore,
    model: PlayerViewModel,
    tap: AudioTapProviding?,
    scale: Int
) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    // The wide, short dock-bar proportions. `scale` lets the dev open a larger
    // window; the SwiftUI layout is resolution-independent so it just scales the
    // logical size.
    let baseWidth = 560.0
    let baseHeight = 132.0
    let contentRect = NSRect(
        x: 0, y: 0,
        width: baseWidth * Double(scale),
        height: baseHeight * Double(scale)
    )

    let scene = DwanimPlayerScene(core: core, model: model)
    let hostingView = NSHostingView(rootView: scene)
    hostingView.frame = contentRect

    let controller = DefaultSkinController(core: core, model: model, tap: tap)
    liveDefaultSkinController = controller

    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.title = "Dwanim"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    // A dark backing colour so the rounded glass corners blend into the window
    // chrome rather than flashing white at the edges.
    window.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.18, alpha: 1)
    window.delegate = controller
    window.contentView = hostingView
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.delegate = controller
    controller.start()

    app.activate(ignoringOtherApps: true)
    app.run()

    exit(0)
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors the other harness modes.
private func defaultSkinFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
