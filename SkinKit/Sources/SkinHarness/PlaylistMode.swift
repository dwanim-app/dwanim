import AppKit
import CoreGraphics
import CoreText
import Foundation
import PlaybackKit
import PlayerCore
import SkinKit
import SkinKitImageIO
import SkinRender

// SkinHarness playlist mode: a dev-only path that opens the classic playlist
// (PLEDIT) window for a skin and draws the live track list. `main.swift`
// dispatches here when `--playlist` is present.
//
// Usage:
//   SkinHarness --playlist <skin.wsz> <audiofile> [<audiofile>...] [--scale N]
//
// Model (consistent with the rest of the harness "platform shell does platform
// text + window; the pure layer stays pixel-only" split):
//   * The window FRAME is the pure `PlaylistWindowComposer` RGBA8 bitmap, scaled
//     by `--scale` with nearest-neighbor (like `SkinImageView`).
//   * The TRACK LIST text is PLATFORM text drawn here via CoreText, because the
//     classic playlist uses the SYSTEM font named in `pledit.txt` — not a bitmap
//     glyph sheet. The pure layer only tells us WHERE (interiorRect) and WHICH
//     rows (PlaylistLayout.visibleRows); this shell draws the strings.
//   * Mouse-wheel scrolls the list by whole rows (clamped by the pure helper).
//
// The ONLY text drawn is each audio file's own name (the user's file) — no brand
// names anywhere. A skin's baked title-bar art is the user's content.

// MARK: - Argument parsing

private struct PlaylistArguments {
    var skinPath: String
    var audioPaths: [String]
    var scale: Int
}

private let playlistUsage =
    "Usage: SkinHarness --playlist <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"

/// Parse the playlist-mode argument vector. `--playlist` and everything after it
/// is consumed here: the first positional is the skin path, the rest are audio
/// files, and `--scale N` may appear anywhere after the flag.
private func parsePlaylistArguments(_ argv: [String]) -> PlaylistArguments {
    guard let flagIndex = argv.firstIndex(of: "--playlist") else {
        playlistFail("Internal: --playlist dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2

    var index = flagIndex + 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...16).contains(value) else {
                playlistFail(
                    "--scale requires an integer in 1...16 (larger values overflow the "
                        + "scaled-image dimensions). \(playlistUsage)"
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
        playlistFail("Missing required skin path. \(playlistUsage)")
    }
    let audioPaths = Array(positionals.dropFirst())
    guard !audioPaths.isEmpty else {
        playlistFail("Missing required audio file(s). \(playlistUsage)")
    }

    return PlaylistArguments(skinPath: skinPath, audioPaths: audioPaths, scale: scale)
}

// MARK: - Entry point

/// Run the playlist mode and never return: load the skin + audio, open the
/// playlist window, and drive the main run loop. `@MainActor` because it touches
/// AppKit (the window); dispatched from `main.swift` via `MainActor.assumeIsolated`.
@MainActor
func runPlaylistMode() -> Never {
    let arguments = parsePlaylistArguments(CommandLine.arguments)

    let skin = loadPlaylistSkin(at: arguments.skinPath)

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

    openPlaylistWindow(skin: skin, core: core, scale: arguments.scale)
}

/// Load + decode the skin and confirm its playlist frame composes (the playlist
/// window is meaningless without a frame). Mirrors the other modes' fault checks.
private func loadPlaylistSkin(at path: String) -> Skin {
    let url = URL(fileURLWithPath: path)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        playlistFail("Could not read skin file at \(path): \(error.localizedDescription)")
    }

    let skin: Skin
    do {
        skin = try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
    } catch {
        playlistFail("Could not load skin at \(path): \(error)")
    }

    // A representative compose at the default size proves the frame sheet was cut.
    guard PlaylistWindowComposer.compose(
        skin,
        width: PlaylistWindowGeometry.defaultWidth,
        height: PlaylistWindowGeometry.defaultHeight
    ) != nil else {
        playlistFail(
            "Could not compose the playlist window for skin at \(path): "
                + "no playlist frame (pledit.bmp)."
        )
    }
    return skin
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors the other harness modes.
private func playlistFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
