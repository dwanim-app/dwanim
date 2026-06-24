import Foundation
import SkinKit

// MARK: - SkinCanvas
//
// The shared RGBA8 blit primitive for the static/dynamic compositing seam. It
// needs NO graphics framework: overlaying is just copying a sprite's pixels onto
// a base buffer at an (x, y) offset, top-left origin, clipped to the base
// bounds. Static composition (`MainWindowComposer`) and dynamic content
// (`BitmapText`, and later the time / visualizer) all go through this one
// primitive, so the blit logic exists in exactly one place.
//
// Sprites are opaque (the decoder forces alpha to 0xFF), so a straight overwrite
// is the correct composite — no alpha blending is needed.

public enum SkinCanvas {

    // MARK: - Overlay

    /// Overlay `sprite` onto `base` at top-left `(x, y)`, opaque overwrite,
    /// clipped to `base`'s bounds. Mutates `base` in place.
    ///
    /// Skips silently (leaving `base` untouched) if either buffer is
    /// size-inconsistent — `pixels.count != width * height * 4` — because copying
    /// such a buffer would read or write out of range and trap. This is the same
    /// fault-tolerance guard the static compositor relies on.
    public static func overlay(
        _ sprite: DecodedBitmap,
        onto base: inout DecodedBitmap,
        x: Int,
        y: Int
    ) {
        // Size-consistency guards: a malformed buffer would trap the row copies.
        guard base.pixels.count == base.width * base.height * 4 else { return }
        guard sprite.pixels.count == sprite.width * sprite.height * 4 else { return }

        let canvasWidth = base.width
        let canvasHeight = base.height

        // Visible column range within the sprite, clipped to the canvas.
        let startColumn = max(0, -x)
        let endColumn = min(sprite.width, canvasWidth - x)
        guard startColumn < endColumn else { return }

        // Visible row range within the sprite, clipped to the canvas.
        let startRow = max(0, -y)
        let endRow = min(sprite.height, canvasHeight - y)
        guard startRow < endRow else { return }

        let visibleWidth = endColumn - startColumn
        let byteCount = visibleWidth * 4

        var pixels = base.pixels
        for row in startRow..<endRow {
            let spriteRowStart = (row * sprite.width + startColumn) * 4
            let canvasX = x + startColumn
            let canvasY = y + row
            let canvasRowStart = (canvasY * canvasWidth + canvasX) * 4

            pixels.replaceSubrange(
                canvasRowStart..<(canvasRowStart + byteCount),
                with: sprite.pixels[spriteRowStart..<(spriteRowStart + byteCount)]
            )
        }
        base = DecodedBitmap(width: canvasWidth, height: canvasHeight, pixels: pixels)
    }
}
