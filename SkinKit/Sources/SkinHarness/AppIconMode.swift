import AppKit
import CoreGraphics
import DwanimUI
import Foundation
import SkinAppKit
import SwiftUI

// SkinHarness app-icon mode: render the deterministic `DwanimUI.AppIconView` at
// each canonical `.iconset` pixel size via SwiftUI `ImageRenderer`, writing the
// ten Apple-named PNGs into `<outDir>/AppIcon.iconset/`.
//
// Usage:
//   SkinHarness --app-icon <outDir>
//
// Each size is rendered NATIVELY: the view is framed at `side` logical points and
// the renderer scale is pinned to 1, so the bitmap comes out exactly
// `side`x`side` PIXELS. We do NOT render one 1024 and downscale — a 16px file is
// 16px art, drawn fresh at that size, so the mark stays crisp. `AppIconView`
// fills a SOLID gradient plate (no `.ultraThinMaterial`), so the render is
// deterministic off-screen and identical at every size.
//
// The size table (names -> pixels) lives in `DwanimUI.AppIconSizes`, shared with
// the unit test that guards the slot list. This mode is harness-only; the pure
// modules and the view stay untouched.

/// Run the app-icon render mode and never return. Hops onto the main actor:
/// `ImageRenderer` is `@MainActor`-only.
func runAppIconMode() -> Never {
    guard let flagIndex = CommandLine.arguments.firstIndex(of: "--app-icon") else {
        appIconFail("Internal: --app-icon dispatched without the flag present.")
    }
    let valueIndex = flagIndex + 1
    guard valueIndex < CommandLine.arguments.count else {
        appIconFail("Missing <outDir>. Usage: SkinHarness --app-icon <outDir>")
    }
    let outDir = CommandLine.arguments[valueIndex]

    MainActor.assumeIsolated {
        renderAppIconSet(outDir: outDir)
    }
    exit(0)
}

/// Render all ten canonical PNGs into `<outDir>/AppIcon.iconset/`. Fails (exit 1)
/// on the first size that does not produce a bitmap or cannot be written.
@MainActor
private func renderAppIconSet(outDir: String) {
    let iconsetURL = URL(fileURLWithPath: outDir)
        .appendingPathComponent("AppIcon.iconset", isDirectory: true)
    do {
        try FileManager.default.createDirectory(
            at: iconsetURL, withIntermediateDirectories: true
        )
    } catch {
        appIconFail("Could not create \(iconsetURL.path): \(error.localizedDescription)")
    }

    for entry in AppIconSizes.entries {
        let side = CGFloat(entry.pixels)
        guard let image = renderIcon(side: side) else {
            appIconFail("Could not render AppIconView at \(entry.pixels)px (\(entry.fileName)).")
        }
        guard image.width == entry.pixels, image.height == entry.pixels else {
            appIconFail(
                "Rendered \(entry.fileName) at \(image.width)x\(image.height) px,"
                + " expected \(entry.pixels)x\(entry.pixels)."
            )
        }
        let outURL = iconsetURL.appendingPathComponent(entry.fileName)
        do {
            try writePNG(image, to: outURL)
        } catch {
            appIconFail("Could not write \(outURL.path): \(error)")
        }
        print("Wrote \(outURL.path) (\(image.width)x\(image.height) px)")
    }

    print("Wrote 10 icon PNGs to \(iconsetURL.path)")
}

/// Render `AppIconView(side:)` to an exact `side`x`side` pixel `CGImage`. Pins the
/// renderer scale to 1 and frames the view at `side` logical points, so the bitmap
/// dimensions equal the pixel size with no rounding or downscale.
@MainActor
private func renderIcon(side: CGFloat) -> CGImage? {
    let view = AppIconView(side: side)
        .frame(width: side, height: side)
    let renderer = ImageRenderer(content: view)
    // scale 1 => 1 logical point maps to 1 output pixel, so width/height in
    // pixels equal `side`. The plate's transparent margin is preserved (the icon
    // is rendered with a transparent backing).
    renderer.scale = 1
    renderer.isOpaque = false
    return renderer.cgImage
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors the other harness modes.
private func appIconFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
