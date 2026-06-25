import AppKit
import CoreGraphics
import Foundation
import PlaybackKit
import PlayerCore
import SkinAppKit
import SkinKit
import SkinKitImageIO
import SkinRender

// SkinHarness interactive mode: a dev-only path that wires the rendered skin
// window to the audio core so clicking the transport buttons actually controls
// playback. This lives in its own file (per the harness's "thin shell, small
// functions" convention); `main.swift` dispatches here when `--interactive` is
// present.
//
// Usage:
//   SkinHarness --interactive <skin.wsz> <audiofile> [<audiofile>...] [--scale N]
//
// This file holds the interactive mode's ARGUMENT PARSING + the `runInteractiveMode`
// ENTRY point + the harness's process-lifetime controller hold + run loop. The
// concrete `InteractiveController` (the live main-window controller) and the
// window-construction logic now live in `SkinAppKit` (so the real app can reuse
// them); this mode CONSTRUCTS them via `SkinAppKit.showInteractiveWindow`.
//
// Flow:
//   1. Load the skin (SkinLoader + ImageIOBitmapDecoder) and confirm it composes.
//   2. Build a PlayerCore over the concrete engine; load the given audio files as
//      a playlist (each Track.title is the file-name stem — the user's own file,
//      so it is fine to display; NO brand title is invented).
//   3. Open the skin window via SkinAppKit, reusing the same scale + region-mask
//      pipeline as the plain window mode. The content view accepts mouse clicks.
//   4. mouseDown -> skin-space coords -> ControlHitTest -> a PlayerCore action.
//   5. A ~0.04s (25 Hz) repeating main-run-loop timer recomposes the window from the live
//      PlayerCore state (time + title overlays, optional pressed-button feedback)
//      and swaps the view's image.
//
// The ONLY text drawn is the audio file's own name (the title) and the MM:SS time
// — no brand names anywhere.

// MARK: - Argument parsing

/// Parsed interactive-mode arguments: the skin path, one-or-more audio files, and
/// the integer zoom.
private struct InteractiveArguments {
    var skinPath: String
    var audioPaths: [String]
    var scale: Int
}

private let interactiveUsage =
    "Usage: SkinHarness --interactive <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"

/// Parse the interactive-mode argument vector. `argv` is the full process
/// argument list; the `--interactive` flag and everything after it is consumed
/// here. The first non-option positional is the skin path; the rest are audio
/// files. `--scale N` may appear anywhere after the flag.
private func parseInteractiveArguments(_ argv: [String]) -> InteractiveArguments {
    guard let flagIndex = argv.firstIndex(of: "--interactive") else {
        interactiveFail("Internal: --interactive dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2

    var index = flagIndex + 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...16).contains(value) else {
                interactiveFail(
                    "--scale requires an integer in 1...16 (larger values overflow the "
                        + "scaled-image dimensions). \(interactiveUsage)"
                )
            }
            scale = value
            index += 2
        default:
            positionals.append(arg)
            index += 1
        }
    }

    guard let skinPath = positionals.first else {
        interactiveFail("Missing required skin path. \(interactiveUsage)")
    }
    let audioPaths = Array(positionals.dropFirst())
    guard !audioPaths.isEmpty else {
        interactiveFail("Missing required audio file(s). \(interactiveUsage)")
    }

    return InteractiveArguments(skinPath: skinPath, audioPaths: audioPaths, scale: scale)
}

// MARK: - Entry point

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var liveController: InteractiveController?

/// Run the interactive mode and never return: it opens the window, starts the
/// redraw loop, and drives the main run loop (exits the process itself).
func runInteractiveMode() -> Never {
    let arguments = parseInteractiveArguments(CommandLine.arguments)

    // Load + compose the skin (fault checks mirror the plain window path).
    let skinURL = URL(fileURLWithPath: arguments.skinPath)
    let skinData: Data
    do {
        skinData = try Data(contentsOf: skinURL)
    } catch {
        interactiveFail("Could not read skin file at \(arguments.skinPath): \(error.localizedDescription)")
    }

    let skin: Skin
    do {
        skin = try SkinLoader.load(skinData, decoder: ImageIOBitmapDecoder())
    } catch {
        interactiveFail("Could not load skin at \(arguments.skinPath): \(error)")
    }

    guard MainWindowComposer.compose(skin) != nil else {
        interactiveFail(
            "Could not compose main window for skin at \(arguments.skinPath): "
                + "no main-window background (main.bmp/background)."
        )
    }

    // Build the core and load the audio files. Each Track.title is the file's own
    // name stem (the user's file — fine to display); NO brand title is invented.
    let tracks = arguments.audioPaths.map { path -> Track in
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        return Track(url: url, title: stem)
    }
    // Keep the concrete engine so it can be opt-in cast to `AudioTapProviding`
    // for the spectrum tap and `TrackFormatProviding` for the kbps/kHz boxes
    // (neither PCM nor format metadata flows through PlayerCore's transport).
    let engine = AVAudioEnginePlayer()
    let core = PlayerCore(engine: engine)
    core.load(tracks)

    // Open the window via SkinAppKit, reusing the existing scale + region-mask
    // pipeline.
    let region = skin.region.flatMap { $0.polygons.isEmpty ? nil : $0 }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let handle: InteractiveWindowHandle
    do {
        handle = try showInteractiveWindow(
            skin: skin, core: core, tap: engine, format: engine,
            region: region, scale: arguments.scale, title: "SkinHarness"
        )
    } catch {
        interactiveFail("Failed to render skin: \(error)")
    }
    liveController = handle.controller

    // Belt and suspenders: also exit when the last window closes, in case a close
    // path bypasses the delegate.
    app.delegate = handle.controller

    app.activate(ignoringOtherApps: true)
    app.run()

    // app.run() does not return in normal use; treat a return as a clean stop.
    exit(0)
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors `main.swift`'s `fail`,
/// kept local so the interactive mode is self-contained.
private func interactiveFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
