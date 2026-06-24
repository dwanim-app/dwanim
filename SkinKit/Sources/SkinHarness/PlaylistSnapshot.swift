import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinKitImageIO
import SkinRender

// Headless playlist-window snapshot: render the playlist frame + a synthetic
// multi-track list to a PNG offscreen (no NSWindow, no run loop), so the
// track-list view can be verified without opening the blocking window.
//
// Usage:
//   SkinHarness --playlist-snapshot <skin.wsz> <out.png> [--scale N] [--selected I]
//
// The synthetic titles are injected here ONLY for the snapshot; they exercise
// the row layout, the now-playing-row color, the SELECTED-row highlight
// (selectedBackground, distinct from the now-playing row), and clip-to-interior
// behavior. They are generic placeholders — no brand names. `--selected I` injects
// a selected index (default `snapshotSelectedIndex`); pass it to verify a
// specific row's highlight.

/// Synthetic track titles for the snapshot — enough to overflow the interior so
/// the visible-row clamp is exercised. Generic placeholders (the user's own files
/// would supply real names in the live mode).
private let snapshotTitles = [
    "01 - Opening Theme",
    "02 - Morning Light",
    "03 - River Walk",
    "04 - The Long Road",
    "05 - Quiet Hours",
    "06 - City Lights",
    "07 - Distant Shore",
    "08 - Evening Calm",
    "09 - Night Drive",
    "10 - Afterglow",
    "11 - Closing Credits",
    "12 - Hidden Track"
]

/// The index marked as the currently playing row in the snapshot.
private let snapshotCurrentIndex = 4
/// The index marked as the SELECTED row in the snapshot — distinct from the
/// now-playing row so the snapshot shows the `selectedBackground` highlight and
/// the `currentText` now-playing row as two different rows. Overridable via
/// `--selected`.
private let snapshotSelectedIndex = 2

func runPlaylistSnapshotMode() -> Never {
    guard let flagIndex = CommandLine.arguments.firstIndex(of: "--playlist-snapshot") else {
        snapshotFail("Internal: --playlist-snapshot dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2
    var selectedIndex = snapshotSelectedIndex
    var index = flagIndex + 1
    while index < CommandLine.arguments.count {
        let arg = CommandLine.arguments[index]
        if arg == "--scale" {
            guard index + 1 < CommandLine.arguments.count,
                  let value = Int(CommandLine.arguments[index + 1]), (1...16).contains(value) else {
                snapshotFail("--scale requires an integer in 1...16.")
            }
            scale = value
            index += 2
        } else if arg == "--selected" {
            guard index + 1 < CommandLine.arguments.count,
                  let value = Int(CommandLine.arguments[index + 1]), value >= 0 else {
                snapshotFail("--selected requires a non-negative integer row index.")
            }
            selectedIndex = value
            index += 2
        } else {
            positionals.append(arg)
            index += 1
        }
    }

    guard positionals.count >= 2 else {
        snapshotFail("Usage: SkinHarness --playlist-snapshot <skin.wsz> <out.png> [--scale N] [--selected I]")
    }
    let skinPath = positionals[0]
    let outPath = positionals[1]

    // Load the skin.
    let url = URL(fileURLWithPath: skinPath)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        snapshotFail("Could not read skin at \(skinPath): \(error.localizedDescription)")
    }
    let skin: Skin
    do {
        skin = try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
    } catch {
        snapshotFail("Could not load skin at \(skinPath): \(error)")
    }

    let width = PlaylistWindowGeometry.defaultWidth
    let height = PlaylistWindowGeometry.defaultHeight
    guard let frame = PlaylistWindowComposer.compose(skin, width: width, height: height),
          let frameImage = CGImageConversion.makeImage(from: frame) else {
        snapshotFail("Could not compose the playlist frame for \(skinPath) (no pledit.bmp?).")
    }

    // Synthetic tracks (snapshot only). The URL is a placeholder; only the title
    // is shown.
    let tracks = snapshotTitles.map { title in
        Track(url: URL(fileURLWithPath: "/tmp/\(title).mp3"), title: title)
    }

    let outWidth = frame.width * scale
    let outHeight = frame.height * scale

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: outWidth,
              height: outHeight,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  | CGBitmapInfo.byteOrder32Big.rawValue
          ) else {
        snapshotFail("Could not create the offscreen bitmap context.")
    }

    // Frame bitmap (nearest-neighbor scale) then the track list, both bottom-left
    // origin, matching the live view's draw order.
    context.interpolationQuality = .none
    context.draw(frameImage, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

    drawPlaylistTrackList(
        in: context,
        skin: skin,
        tracks: tracks,
        currentIndex: snapshotCurrentIndex,
        selectedIndex: selectedIndex,
        scrollRow: 0,
        skinWidth: frame.width,
        skinHeight: frame.height,
        scale: scale
    )

    guard let image = context.makeImage() else {
        snapshotFail("Could not finalize the snapshot image.")
    }

    do {
        try writePNG(image, to: URL(fileURLWithPath: outPath))
    } catch {
        snapshotFail("Could not write the snapshot PNG to \(outPath): \(error)")
    }

    print("Wrote \(outPath) (\(outWidth)x\(outHeight) px)")
    exit(0)
}

private func snapshotFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
