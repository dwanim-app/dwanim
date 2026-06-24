import AppKit
import Foundation
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

/// The composed image plus whether a custom (non-rectangular) shape was applied.
/// `isShaped` is `true` only when the skin declared region polygons and the mask
/// actually zeroed some out-of-region alpha; the window path uses it to decide
/// between a normal titled window and a borderless transparent (shaped) one.
private struct ComposedResult {
    var image: CGImage
    var isShaped: Bool
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

    // Non-rectangular window shape: if the skin declared region polygons, build a
    // visibility mask at the composed bitmap's size and zero the alpha of every
    // out-of-region pixel. This is applied AFTER compose + text (compose itself
    // stays rectangular / opaque). A nil or empty region leaves the bitmap fully
    // opaque, so unshaped skins behave exactly as before.
    var isShaped = false
    if let region = skin.region, !region.polygons.isEmpty {
        let mask = RegionCoverage.mask(
            region,
            width: composed.width,
            height: composed.height
        )
        RegionCoverage.applyMask(mask, to: &composed)
        // Only treat as shaped if the mask actually carved something away; a
        // region that happens to cover the whole canvas stays rectangular.
        isShaped = mask.contains(false)
    }

    guard let image = CGImageConversion.makeImage(from: composed) else {
        fail("Could not build an image from the composed main window for skin at \(path).")
    }
    return ComposedResult(image: image, isShaped: isShaped)
}

// MARK: - Modes

private func runPNGMode(image: CGImage, output: String, scale: Int) {
    do {
        let scaled = try scaledImage(image, scale: scale)
        try writePNG(scaled.image, to: URL(fileURLWithPath: output))
        print("Wrote \(output) (\(scaled.width)x\(scaled.height) px)")
        exit(0)
    } catch {
        fail("Failed to render PNG: \(error)")
    }
}

private func runWindowMode(image: CGImage, scale: Int, isShaped: Bool) {
    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        fail("Failed to render skin: \(error)")
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)

    // A shaped skin carries transparent pixels outside its region. To let those
    // show through as a non-rectangular window, the window must be borderless and
    // non-opaque with a clear background; otherwise use the normal titled chrome.
    let window: NSWindow
    if isShaped {
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
    } else {
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SkinHarness"
    }
    window.contentView = SkinImageView(image: scaled.image, frame: contentRect)
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
}

// MARK: - Entry point

private let arguments = parseArguments(CommandLine.arguments)
private let composed = loadComposedImage(at: arguments.skinPath, title: arguments.title)

if let output = arguments.pngOutput {
    runPNGMode(image: composed.image, output: output, scale: arguments.scale)
} else {
    runWindowMode(image: composed.image, scale: arguments.scale, isShaped: composed.isShaped)
}
