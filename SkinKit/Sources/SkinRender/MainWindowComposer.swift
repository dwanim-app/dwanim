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
        var pixels = background.pixels // a COPY of the background buffer

        for element in elements {
            guard let sprite = skin.sprite(sheet: element.sheet, name: element.sprite) else {
                continue // fault tolerant: skip missing sprites
            }
            overwrite(
                &pixels,
                canvasWidth: width,
                canvasHeight: height,
                with: sprite,
                atX: element.x,
                atY: element.y
            )
        }

        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    // MARK: - Overwrite

    /// Copies `sprite`'s pixels into `canvas` at top-left `(originX, originY)`,
    /// row by row, clipping any part that falls outside the canvas bounds.
    private static func overwrite(
        _ canvas: inout [UInt8],
        canvasWidth: Int,
        canvasHeight: Int,
        with sprite: DecodedBitmap,
        atX originX: Int,
        atY originY: Int
    ) {
        // Visible column range within the sprite, clipped to the canvas.
        let startColumn = max(0, -originX)
        let endColumn = min(sprite.width, canvasWidth - originX)
        guard startColumn < endColumn else { return }

        // Visible row range within the sprite, clipped to the canvas.
        let startRow = max(0, -originY)
        let endRow = min(sprite.height, canvasHeight - originY)
        guard startRow < endRow else { return }

        let visibleWidth = endColumn - startColumn
        let byteCount = visibleWidth * 4

        for row in startRow..<endRow {
            let spriteRowStart = (row * sprite.width + startColumn) * 4
            let canvasX = originX + startColumn
            let canvasY = originY + row
            let canvasRowStart = (canvasY * canvasWidth + canvasX) * 4

            canvas.replaceSubrange(
                canvasRowStart..<(canvasRowStart + byteCount),
                with: sprite.pixels[spriteRowStart..<(spriteRowStart + byteCount)]
            )
        }
    }
}
