import AppKit
import CoreGraphics
import Foundation
import PlaybackKit
import PlayerCore
import SkinKit
import SkinKitImageIO
import SkinRender

// SkinHarness EQ mode: a dev-only path that opens the classic equalizer (EQ)
// window for a skin and makes it INTERACTIVE — dragging a slider really changes
// the sound, because the slider drives the live `PlayerCore` equalizer, which
// mirrors to the real `AVAudioUnitEQ` in the engine (the DSP proven in the EQ
// engine increment). `main.swift` dispatches here when `--eq` is present.
//
// Usage:
//   SkinHarness --eq <skin.wsz> <audiofile> [<audiofile>...] [--scale N]
//
// Flow:
//   1. Load the skin (SkinLoader + ImageIOBitmapDecoder) and confirm the EQ face
//      composes (EQWindowComposer needs eqmain.bmp/background).
//   2. Build a PlayerCore over the concrete AVAudioEnginePlayer; load the given
//      audio files as a playlist and start playback so the EQ is audible.
//   3. Open an NSWindow hosting an EQ content view that draws
//      EQWindowComposer.compose(...) with the CURRENT PlayerCore.equalizer values,
//      scaled nearest-neighbor (same scale + flip pipeline as --interactive).
//   4. mouseDown / mouseDragged -> ControlHitTest.skinPoint (the SAME verified
//      flip used elsewhere) -> EQWindowLayout.slider(atSkinX:) picks the column ->
//      EQWindowLayout.thumbGain(forThumbTopY:) maps the skin-space y to a gain ->
//      PlayerCore.setEQPreamp / setEQBand drives the real AVAudioUnitEQ -> recompose
//      so the thumb follows the cursor AND the sound changes live.
//   5. A click on the ON button region toggles PlayerCore.setEQEnabled.
//
// DEFERRED (documented, not built here): the colored band-graph response CURVE
// line over the graph area; the AUTO button (no auto-preset flag is modelled —
// it is a no-op); the windowshade (rolled-up) variant and drag-resize (the EQ
// window is a fixed 275x116, unlike the resizable PLEDIT).
//
// NO text is drawn (the preset display is deferred), so there are no brand names.
//
// This file holds the EQ mode's ARGUMENT PARSING + the `runEQMode` ENTRY point
// (one primary concern per file, §12). The interactive view is the shared
// `SkinAppKit.ScaledImageView`; the controller + window setup, and the headless
// snapshot live in `EQController.swift` / `EQWindowSetup.swift`, and
// `EQSnapshot.swift`.

// MARK: - Argument parsing

/// Parsed EQ-mode arguments: the skin path, one-or-more audio files, the zoom.
struct EQArguments {
    var skinPath: String
    var audioPaths: [String]
    var scale: Int
}

let eqUsage =
    "Usage: SkinHarness --eq <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"

/// Parse the EQ-mode argument vector. `argv` is the full process argument list;
/// the `--eq` flag and everything after it is consumed here. The first non-option
/// positional is the skin path; the rest are audio files. `--scale N` may appear
/// anywhere after the flag.
func parseEQArguments(_ argv: [String]) -> EQArguments {
    guard let flagIndex = argv.firstIndex(of: "--eq") else {
        eqFail("Internal: --eq dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2

    var index = flagIndex + 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...16).contains(value) else {
                eqFail(
                    "--scale requires an integer in 1...16 (larger values overflow the "
                        + "scaled-image dimensions). \(eqUsage)"
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
        eqFail("Missing required skin path. \(eqUsage)")
    }
    let audioPaths = Array(positionals.dropFirst())
    guard !audioPaths.isEmpty else {
        eqFail("Missing required audio file(s). \(eqUsage)")
    }

    return EQArguments(skinPath: skinPath, audioPaths: audioPaths, scale: scale)
}

// MARK: - Entry point

/// Run the EQ mode and never return: load the skin + audio, open the EQ window,
/// start playback, and drive the main run loop (exits the process itself).
///
/// `@MainActor` because it builds the `@MainActor` `PlayerCore`, drives it
/// (`setEQEnabled` / `play`), and opens the window (main-actor AppKit). The harness
/// runs on the main thread; `main.swift` dispatches it from the main-actor context.
@MainActor
func runEQMode() -> Never {
    let arguments = parseEQArguments(CommandLine.arguments)

    // Load + compose the skin (fault checks mirror the other window paths).
    let skinURL = URL(fileURLWithPath: arguments.skinPath)
    let skinData: Data
    do {
        skinData = try Data(contentsOf: skinURL)
    } catch {
        eqFail("Could not read skin file at \(arguments.skinPath): \(error.localizedDescription)")
    }

    let skin: Skin
    do {
        skin = try SkinLoader.load(skinData, decoder: ImageIOBitmapDecoder())
    } catch {
        eqFail("Could not load skin at \(arguments.skinPath): \(error)")
    }

    // Confirm the EQ face composes (needs eqmain.bmp/background).
    guard EQWindowComposer.compose(skin, enabled: false, preamp: 0, bands: []) != nil else {
        eqFail(
            "Could not compose the EQ window for skin at \(arguments.skinPath): "
                + "no EQ-window background (eqmain.bmp/background)."
        )
    }

    // Build the core and load the audio files; each Track.title is the file's own
    // name stem (the user's file). Start playback so the EQ is audible.
    let tracks = arguments.audioPaths.map { path -> Track in
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        return Track(url: url, title: stem)
    }
    let engine = AVAudioEnginePlayer()
    let core = PlayerCore(engine: engine)
    core.load(tracks)
    // Enable the equalizer and start playback so a drag is immediately audible.
    core.setEQEnabled(true)
    core.play()

    openEQWindow(skin: skin, core: core, scale: arguments.scale)
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors the other modes' `fail`,
/// kept local so the EQ mode is self-contained.
func eqFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
