import AppKit
import Foundation
import SkinKit
import SkinKitImageIO

// SkinHarness: a dev-only shell that loads a classic skin archive and draws its
// main window background. This is the shell layer (it may import AppKit /
// CoreGraphics / ImageIO); the SkinKit core stays platform-neutral.
//
// Usage: SkinHarness <path-to.wsz> [--png <out.png>] [--scale N]
//
// TODO: This increment renders only the main-window BACKGROUND ("main.bmp"
// sprite "background"). Compositing the title bar, transport buttons, and
// number displays at their on-window positions is the next increment and
// requires the window-layout coordinate map, which is intentionally not done
// here.

// MARK: - Constants

private let mainSheet = "main.bmp"
private let backgroundSprite = "background"

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

private func loadBackgroundImage(at path: String) -> CGImage {
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

    guard let bitmap = skin.sprite(sheet: mainSheet, name: backgroundSprite) else {
        fail("Skin at \(path) has no main-window background (\(mainSheet)/\(backgroundSprite)).")
    }

    guard let image = CGImageConversion.makeImage(from: bitmap) else {
        fail("Could not build an image from the main-window background.")
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
private let backgroundImage = loadBackgroundImage(at: arguments.skinPath)

if let output = arguments.pngOutput {
    runPNGMode(image: backgroundImage, output: output, scale: arguments.scale)
} else {
    runWindowMode(image: backgroundImage, scale: arguments.scale)
}
