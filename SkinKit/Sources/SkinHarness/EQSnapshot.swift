import AppKit
import CoreGraphics
import Foundation
import SkinKit
import SkinKitImageIO
import SkinRender

// Headless EQ-window snapshot: compose the EQ face at a representative state (a
// curve dialed in + the equalizer ON) and write it to a PNG offscreen — NO
// NSWindow, no run loop, no audio — so the interactive face can be verified
// without opening the blocking window. It runs the SAME EQWindowComposer the live
// window draws, so the snapshot is faithful to what a user sees. A distinct
// responsibility from the live mode (one primary concern per file, §12), split
// out of `EQMode.swift`, mirroring `PlaylistSnapshot.swift`.
//
// Usage:
//   SkinHarness --eq-snapshot <skin.wsz> <out.png> [--scale N]

/// A representative non-flat curve so the snapshot shows the thumbs spread across
/// the track (a gentle "smile": boost the lows and highs, cut the mids), plus a
/// preamp lift. Exercises the gain→thumb-y placement across the full ±12 range.
private let snapshotBands: [Double] = [12, 8, 4, 0, -4, -4, 0, 4, 8, 12]
private let snapshotPreamp: Double = 6

func runEQSnapshotMode() -> Never {
    guard let flagIndex = CommandLine.arguments.firstIndex(of: "--eq-snapshot") else {
        eqSnapshotFail("Internal: --eq-snapshot dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2
    var index = flagIndex + 1
    while index < CommandLine.arguments.count {
        let arg = CommandLine.arguments[index]
        if arg == "--scale" {
            guard index + 1 < CommandLine.arguments.count,
                  let value = Int(CommandLine.arguments[index + 1]), (1...16).contains(value) else {
                eqSnapshotFail("--scale requires an integer in 1...16.")
            }
            scale = value
            index += 2
        } else {
            positionals.append(arg)
            index += 1
        }
    }

    guard positionals.count >= 2 else {
        eqSnapshotFail("Usage: SkinHarness --eq-snapshot <skin.wsz> <out.png> [--scale N]")
    }
    let skinPath = positionals[0]
    let outPath = positionals[1]

    let url = URL(fileURLWithPath: skinPath)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        eqSnapshotFail("Could not read skin at \(skinPath): \(error.localizedDescription)")
    }
    let skin: Skin
    do {
        skin = try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
    } catch {
        eqSnapshotFail("Could not load skin at \(skinPath): \(error)")
    }

    // Compose the EQ face with the equalizer ON and the representative curve — the
    // SAME composer the live window uses.
    guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: snapshotPreamp, bands: snapshotBands
          ),
          let image = CGImageConversion.makeImage(from: composed) else {
        eqSnapshotFail("Could not compose the EQ window for \(skinPath) (no eqmain.bmp?).")
    }

    do {
        let scaled = try scaledImage(image, scale: scale)
        try writePNG(scaled.image, to: URL(fileURLWithPath: outPath))
        print("Wrote \(outPath) (\(scaled.width)x\(scaled.height) px)")
        exit(0)
    } catch {
        eqSnapshotFail("Could not write the EQ snapshot PNG to \(outPath): \(error)")
    }
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. A distinct copy for the snapshot's
/// separate responsibility (mirrors `PlaylistSnapshot.swift`'s `snapshotFail`).
private func eqSnapshotFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
