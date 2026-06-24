import Foundation
import SkinKit

// MARK: - MainWindowComposer
//
// Pure RGBA8 compositor for the classic main player window. It needs NO graphics
// framework: compositing is just copying sprite pixels onto a copy of the
// background buffer at each element's (x, y). Everything stays in
// `DecodedBitmap`'s top-left-origin RGBA8 space, so there is NO vertical flip.
//
// Sprites are opaque (the decoder forces alpha to 0xFF), so a straight overwrite
// is the correct composite — no alpha blending is needed. Any part of a sprite
// that extends past the background bounds is clipped, never written out of range.

public enum MainWindowComposer {

    // MARK: - Compose (public)

    /// Composite the main window into a single RGBA8 bitmap: start from a COPY of
    /// `main.bmp`'s background, then overlay each `MainWindowLayout` element's
    /// sprite at its (x, y) (top-left origin). Returns `nil` if the background
    /// sprite is absent.
    public static func compose(_ skin: Skin) -> DecodedBitmap? {
        compose(skin, elements: MainWindowLayout.elements)
    }

    // MARK: - Compose (element-parameterized)

    /// Same as `compose(_:)` but with an explicit element list, so tests can
    /// drive placement, draw order, missing-sprite, and clipping cases with
    /// synthetic layouts. Elements are drawn in order, back to front.
    static func compose(_ skin: Skin, elements: [WindowElement]) -> DecodedBitmap? {
        guard let background = skin.sprite(sheet: "main.bmp", name: "background") else {
            return nil
        }

        let width = background.width
        let height = background.height
        // `DecodedBitmap` does not enforce that its backing buffer actually holds
        // `width * height * 4` bytes. An undersized background would make the row
        // copies below read/write out of range and trap, so treat a malformed
        // background as no usable background (same guard class as
        // `SpriteCutter.crop`).
        guard background.pixels.count == width * height * 4 else {
            return nil
        }

        // Start from a COPY of the background buffer, then overlay each element
        // through the shared `SkinCanvas.overlay` blit primitive (the
        // static/dynamic compositing seam). `overlay` clips to bounds and skips
        // any size-inconsistent sprite, so missing or malformed sprites are
        // fault-tolerant here too.
        var canvas = DecodedBitmap(width: width, height: height, pixels: background.pixels)

        for element in elements {
            guard let sprite = skin.sprite(sheet: element.sheet, name: element.sprite) else {
                continue // fault tolerant: skip missing sprites
            }
            SkinCanvas.overlay(sprite, onto: &canvas, x: element.x, y: element.y)
        }

        return canvas
    }
}
