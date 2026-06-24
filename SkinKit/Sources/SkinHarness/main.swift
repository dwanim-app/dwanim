import AppKit
import Foundation
import SkinKit
import SkinKitImageIO
import SkinRender

// SkinHarness: a dev-only shell that loads a classic skin archive and draws its
// composed main window. This is the shell layer (it may import AppKit /
// CoreGraphics / ImageIO); the SkinKit core stays platform-neutral.
//
// Usage: SkinHarness <path-to.wsz> [--png <out.png>] [--scale N]
//
// The harness composes the main window via `MainWindowComposer` (the pure RGBA8
// compositor in `SkinRender`): it copies the "main.bmp" background, then
// overlays each static control from the `MainWindowLayout` coordinate table
// (title bar, transport buttons, shuffle / repeat, position track, volume /
// balance backgrounds, mono / stereo) at its on-window position. Missing
// sprites are skipped (fault tolerant). The composed `DecodedBitmap` is then
// bridged to a `CGImage` here in the shell for scaling and PNG / window output.
//
// TODO: the time / number display and the scrolling song title are deferred
// (they need dynamic content plus the provisional text.bmp glyph map).

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
}

private func parseArguments(_ argv: [String]) -> Arguments {
    var skinPath: String?
    var pngOutput: String?
    var scale = 2

    var index = 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--png":
            guard index + 1 < argv.count else {
                fail("Missing value for --png. Usage: SkinHarness <path.wsz> [--png <out.png>] [--scale N]")
            }
            pngOutput = argv[index + 1]
            index += 2
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), value >= 1 else {
                fail("--scale requires a positive integer. Usage: SkinHarness <path.wsz> [--png <out.png>] [--scale N]")
            }
            scale = value
            index += 2
        default:
            if skinPath == nil {
                skinPath = arg
            } else {
                fail("Unexpected argument: \(arg). Usage: SkinHarness <path.wsz> [--png <out.png>] [--scale N]")
            }
            index += 1
        }
    }

    guard let path = skinPath else {
        fail("Missing required skin path. Usage: SkinHarness <path.wsz> [--png <out.png>] [--scale N]")
    }

    return Arguments(skinPath: path, pngOutput: pngOutput, scale: scale)
}

// MARK: - Loading

private func loadComposedImage(at path: String) -> CGImage {
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

    guard let composed = MainWindowComposer.compose(skin) else {
        fail("Could not compose main window for skin at \(path): "
            + "no main-window background (main.bmp/background).")
    }

    guard let image = CGImageConversion.makeImage(from: composed) else {
        fail("Could not build an image from the composed main window for skin at \(path).")
    }
    return image
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

private func runWindowMode(image: CGImage, scale: Int) {
    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        fail("Failed to render skin: \(error)")
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "SkinHarness"
    window.contentView = SkinImageView(image: scaled.image, frame: contentRect)
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.activate(ignoringOtherApps: true)
    app.run()
}

// MARK: - Entry point

private let arguments = parseArguments(CommandLine.arguments)
private let composedImage = loadComposedImage(at: arguments.skinPath)

if let output = arguments.pngOutput {
    runPNGMode(image: composedImage, output: output, scale: arguments.scale)
} else {
    runWindowMode(image: composedImage, scale: arguments.scale)
}
