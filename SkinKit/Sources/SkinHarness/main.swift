import AppKit
import Foundation
import SkinAppKit
import SkinKit
import SkinKitImageIO
import SkinRender

// SkinHarness: a dev-only shell that loads a classic skin archive and draws its
// composed main window. This is the shell layer (it may import AppKit /
// CoreGraphics / ImageIO); the SkinKit core stays platform-neutral.
//
// Usage: SkinHarness <path-to.wsz> [--png <out.png>] [--scale N] [--title <text>]
//
// The harness composes the main window via `MainWindowComposer` (the pure RGBA8
// compositor in `SkinRender`): it copies the "main.bmp" background, then
// overlays each static control from the `MainWindowLayout` coordinate table
// (title bar, transport buttons, shuffle / repeat, position track, volume /
// balance backgrounds, mono / stereo) at its on-window position. Missing
// sprites are skipped (fault tolerant). It then patches dynamic content onto the
// composed base buffer through `SkinRender.BitmapText`: a placeholder song title
// (default "DWANIM"; override with --title) drawn from the text.bmp glyph font,
// and a 00:00 time display drawn from the numbers.bmp digits. The composed
// `DecodedBitmap` is then bridged to a `CGImage` here in the shell for scaling
// and PNG / window output.
//
// The default title is a neutral placeholder on purpose: the skin's filename is
// NOT used, because filenames may contain third-party brand names.

// MARK: - Failure handling

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - Argument parsing

private struct Arguments {
    var skinPath: String
    var pngOutput: String?
    var scale: Int
    var title: String
}

private let usage = "Usage: SkinHarness <path.wsz> [--png <out.png>] [--scale N] [--title <text>]"
    + "\n   or: SkinHarness --play <audiofile>"
    + "\n   or: SkinHarness --interactive <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"
    + "\n   or: SkinHarness --playlist <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"
    + "\n   or: SkinHarness --eq <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"
    + "\n   or: SkinHarness --default-skin <audiofile> [<audiofile>...] [--scale N]"
    + "\n   or: SkinHarness --app-icon <outDir>"

private func parseArguments(_ argv: [String]) -> Arguments {
    var skinPath: String?
    var pngOutput: String?
    var scale = 2
    // Neutral default placeholder. NOT derived from the skin filename, which may
    // carry a third-party brand name.
    var title = "DWANIM"

    var index = 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--png":
            guard index + 1 < argv.count else {
                fail("Missing value for --png. \(usage)")
            }
            pngOutput = argv[index + 1]
            index += 2
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...16).contains(value) else {
                fail("--scale requires an integer in 1...16 (larger values overflow the scaled-image dimensions). \(usage)")
            }
            scale = value
            index += 2
        case "--title":
            guard index + 1 < argv.count else {
                fail("Missing value for --title. \(usage)")
            }
            title = argv[index + 1]
            index += 2
        default:
            if skinPath == nil {
                skinPath = arg
            } else {
                fail("Unexpected argument: \(arg). \(usage)")
            }
            index += 1
        }
    }

    guard let path = skinPath else {
        fail("Missing required skin path. \(usage)")
    }

    return Arguments(skinPath: path, pngOutput: pngOutput, scale: scale, title: title)
}

// MARK: - Loading

/// The composed OPAQUE main-window bitmap plus the skin's region (if any).
///
/// The bitmap is fully opaque — compose + text are rectangular and NO alpha
/// masking is baked in here. Geometry is kept SEPARATE from pixels: the window
/// path shapes the window/layer with a region mask while the content stays
/// opaque (needed for future hit-testing), and the `--png` path bakes the region
/// into alpha on its own copy. `region` is non-nil only when the skin declared a
/// custom shape; an empty-polygon region is normalized to `nil`.
private struct ComposedResult {
    var bitmap: DecodedBitmap
    var region: SkinRegion?
}

private func loadComposedImage(at path: String, title: String) -> ComposedResult {
    let url = URL(fileURLWithPath: path)

    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        fail("Could not read skin file at \(path): \(error.localizedDescription)")
    }

    let skin: Skin
    do {
        skin = try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
    } catch {
        fail("Could not load skin at \(path): \(error)")
    }

    guard var composed = MainWindowComposer.compose(skin) else {
        fail("Could not compose main window for skin at \(path): "
            + "no main-window background (main.bmp/background).")
    }

    // Patch dynamic content onto the composed base buffer via the SkinRender
    // text renderer: a placeholder song title and a 00:00 time display, drawn at
    // the provisional layout origins. Both are fault tolerant (missing glyphs /
    // digits advance blank), so this never fails the render.
    BitmapText.draw(
        title,
        from: skin,
        onto: &composed,
        x: MainWindowLayout.titleTextOrigin.x,
        y: MainWindowLayout.titleTextOrigin.y,
        maxWidth: MainWindowLayout.titleTextWidth
    )
    BitmapText.drawTime(
        minutes: 0,
        seconds: 0,
        from: skin,
        onto: &composed,
        x: MainWindowLayout.timeDisplayOrigin.x,
        y: MainWindowLayout.timeDisplayOrigin.y
    )

    // The composed bitmap stays OPAQUE here. The shape (if any) is applied per
    // output mode: baked into alpha for --png, or carried as a window-level
    // layer mask for the live window. Normalize an empty-polygon region to nil.
    let region = skin.region.flatMap { $0.polygons.isEmpty ? nil : $0 }
    return ComposedResult(bitmap: composed, region: region)
}

// MARK: - Modes

/// PNG export. A PNG has no "window", so baking the region into the alpha channel
/// is the legitimate way to ship a shaped image (transparent outside the region)
/// — and it's how the shape is visually verified. The bake happens on a COPY of
/// the composed bitmap, so the in-memory `DecodedBitmap` stays opaque.
private func runPNGMode(bitmap: DecodedBitmap, region: SkinRegion?, output: String, scale: Int) {
    var shaped = bitmap
    if let region {
        let mask = RegionCoverage.mask(region, width: shaped.width, height: shaped.height)
        RegionCoverage.applyMask(mask, to: &shaped)
    }

    guard let image = CGImageConversion.makeImage(from: shaped) else {
        fail("Could not build an image from the composed main window.")
    }

    do {
        let scaled = try scaledImage(image, scale: scale)
        try writePNG(scaled.image, to: URL(fileURLWithPath: output))
        print("Wrote \(output) (\(scaled.width)x\(scaled.height) px)")
        exit(0)
    } catch {
        fail("Failed to render PNG: \(error)")
    }
}

/// Live window. The displayed content image stays OPAQUE; a non-rectangular skin
/// is shaped at the WINDOW/LAYER level via a `CAShapeLayer` mask derived from the
/// region polygons (geometry kept separate from pixels). When the skin declares
/// no region, the normal titled/opaque window is used.
private func runWindowMode(bitmap: DecodedBitmap, region: SkinRegion?, scale: Int) {
    guard let image = CGImageConversion.makeImage(from: bitmap) else {
        fail("Could not build an image from the composed main window.")
    }

    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        fail("Failed to render skin: \(error)")
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let contentView = SkinImageView(image: scaled.image, frame: contentRect)

    // Build the window-level mask first: a region whose polygons cover nothing
    // fillable yields no mask, so the skin renders as a normal rectangular window.
    let maskLayer: CAShapeLayer? = region.flatMap { region in
        RegionMaskLayer.make(
            for: region,
            skinHeight: bitmap.height,
            scale: scale,
            scaledWidth: scaled.width,
            scaledHeight: scaled.height
        )
    }

    // The shared region-window builder applies the borderless/masked vs titled
    // chrome decision: a shaped window stays opaque in content but is clipped by
    // the CAShapeLayer mask; a no-region skin gets a plain titled window.
    let window = RegionWindowBuilder.make(
        contentRect: contentRect,
        contentView: contentView,
        maskLayer: maskLayer,
        title: "SkinHarness"
    )
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
}

// MARK: - Entry point

// Interactive mode is a separate path: `--interactive <skin.wsz> <audiofile>...`
// opens the rendered skin window and wires its transport buttons to a live
// `PlayerCore`. It is handled in `InteractiveMode.swift`; dispatch here before
// skin-path parsing so its positional audio files are not mistaken for extra
// `.wsz` arguments. `runInteractiveMode` never returns (it drives the run loop).
if CommandLine.arguments.contains("--interactive") {
    runInteractiveMode()
}

// Playlist snapshot: `--playlist-snapshot <skin.wsz> <out.png>` renders the
// playlist window + a synthetic track list to a PNG offscreen (no window, no run
// loop). Dispatched before `--playlist` so it is matched as its own subcommand.
if CommandLine.arguments.contains("--playlist-snapshot") {
    runPlaylistSnapshotMode()
}

// Playlist mode: `--playlist <skin.wsz> <audiofile>...` opens the classic
// playlist (PLEDIT) window for a skin and draws the live track list. It is
// handled in `PlaylistMode.swift`; dispatch here before skin-path parsing so its
// positional audio files are not mistaken for extra `.wsz` arguments.
// `runPlaylistMode` never returns (it drives the run loop).
if CommandLine.arguments.contains("--playlist") {
    MainActor.assumeIsolated { runPlaylistMode() }
}

// EQ snapshot: `--eq-snapshot <skin.wsz> <out.png>` composes the equalizer face
// at a representative curve + ON state and writes it to a PNG offscreen (no
// window, no run loop, no audio). Dispatched before `--eq` so it is matched as
// its own subcommand. `runEQSnapshotMode` never returns.
if CommandLine.arguments.contains("--eq-snapshot") {
    runEQSnapshotMode()
}

// EQ mode: `--eq <skin.wsz> <audiofile>...` opens the classic equalizer window
// for a skin, wired to a live `PlayerCore` so dragging a slider drives the real
// `AVAudioUnitEQ` (the sound changes). It is handled in `EQMode.swift`; dispatch
// here before skin-path parsing so its positional audio files are not mistaken
// for extra `.wsz` arguments. `runEQMode` never returns (it drives the run loop).
if CommandLine.arguments.contains("--eq") {
    runEQMode()
}

// Default-skin mode: `--default-skin <audiofile>...` opens the app's OWN
// Liquid Glass dock-bar player (no `.wsz`), wired to a live `PlayerCore`. It is
// handled in `DefaultSkinMode.swift`; dispatch here before skin-path parsing so
// its positional audio files are not mistaken for `.wsz` arguments.
// `runDefaultSkinMode` never returns (it drives the run loop). Hop onto the main
// actor explicitly since the entry point is main-actor-isolated (it touches AppKit).
if CommandLine.arguments.contains("--default-skin") {
    MainActor.assumeIsolated { runDefaultSkinMode() }
}

// App-icon mode: `--app-icon <outDir>` renders the deterministic `AppIconView`
// at each canonical .iconset pixel size via SwiftUI ImageRenderer and writes the
// ten Apple-named PNGs to `<outDir>/AppIcon.iconset/` (no window, no run loop, no
// audio). It is handled in `AppIconMode.swift`; dispatch here before skin-path
// parsing so the output directory is not mistaken for a `.wsz` argument.
// `runAppIconMode` never returns.
if CommandLine.arguments.contains("--app-icon") {
    runAppIconMode()
}

// Play mode is a separate path: `--play <audiofile>` exercises the audio engine
// end to end instead of rendering a skin. It is handled in `PlayMode.swift`;
// dispatch here before skin-path parsing so the audio path is not mistaken for a
// `.wsz` argument. `runPlayMode` never returns (it drives the run loop and exits).
if let playIndex = CommandLine.arguments.firstIndex(of: "--play") {
    let valueIndex = playIndex + 1
    guard valueIndex < CommandLine.arguments.count else {
        fail("Missing value for --play. Usage: SkinHarness --play <path-to-audio>")
    }
    runPlayMode(path: CommandLine.arguments[valueIndex])
}

private let arguments = parseArguments(CommandLine.arguments)
private let composed = loadComposedImage(at: arguments.skinPath, title: arguments.title)

if let output = arguments.pngOutput {
    runPNGMode(
        bitmap: composed.bitmap,
        region: composed.region,
        output: output,
        scale: arguments.scale
    )
} else {
    runWindowMode(
        bitmap: composed.bitmap,
        region: composed.region,
        scale: arguments.scale
    )
}
