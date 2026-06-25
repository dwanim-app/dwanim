import Foundation
import SkinKit

// MARK: - PlaylistWindowComposer
//
// Pure RGBA8 compositor for the classic, RESIZABLE playlist (PLEDIT) window
// FRAME. Like `MainWindowComposer` it needs NO graphics framework: compositing
// is copying sprite pixels onto a buffer at (x, y) through the shared
// `SkinCanvas.overlay` blit, all in `DecodedBitmap`'s top-left-origin RGBA8
// space (no vertical flip).
//
// Unlike the main window — a fixed-size single background — the playlist window
// is STRETCHABLE, so its chrome is assembled from corner pieces and TILED fills:
//   * Title bar:   left corner | texture tiled | centered title (once) | texture
//                  tiled | right corner. The texture tiles; the title never does.
//   * Side edges:  left edge and right edge, each tiled vertically down the body.
//   * Bottom frame: bottom-left corner | bottom fill tiled | bottom-right corner.
//   * Interior:    the content area inside the frame, filled with the playlist's
//                  normal background colour (the track list draws here later).
//
// Every tile is clipped to the target bounds by `SkinCanvas.overlay`, so a tile
// that would overrun the last row/column is simply clipped — nothing is written
// out of range. The target size is clamped to a sane minimum (the corners must
// fit) so the corners never overlap into a malformed result.
//
// SCOPE: frame chrome only. The track-list text, the action buttons (add /
// remove / select / misc / list menus), the time/visualizer mini-display, and
// scrollbar interactivity are LATER increments and are not drawn here.

public enum PlaylistWindowComposer {

    // MARK: - Minimum size

    /// The sheet key the frame sprites live in (lowercased, matching `Skin`).
    private static let sheet = "pledit.bmp"

    /// Smallest window width the frame can render without the title-bar corners
    /// (and, equivalently, the bottom corners) overlapping. Below this the result
    /// would be malformed, so `compose` clamps up to it. Derived from the actual
    /// corner widths in `SpriteCoordinates` rather than hardcoded, so it follows
    /// the sprite table if those ever change.
    public static var minimumWidth: Int {
        let title = titleCornerWidths()
        let bottom = bottomCornerWidths()
        // Whichever corner pair is wider sets the floor; +1 guarantees at least a
        // one-pixel fill gap so a tile always has somewhere to land.
        return max(title.left + title.right, bottom.left + bottom.right) + 1
    }

    /// Smallest window height: the title-bar band plus the bottom-frame band plus
    /// at least one row of interior/body between them.
    public static var minimumHeight: Int {
        titleBarHeight() + bottomFrameHeight() + 1
    }

    // MARK: - View size -> skin size (resize)

    /// Map a SCALED view size (the live window's content-view bounds, in scaled
    /// pixels/points) back to the UNSCALED skin-space window size the frame should
    /// be composed at, clamped UP to `minimumWidth`/`minimumHeight` so the corners
    /// always fit.
    ///
    /// This is the resize hinge: as the user drags the window, the AppKit shell
    /// reads its content bounds and asks here for the skin-space dimensions to
    /// re-`compose` (and to feed `interiorRect` / `PlaylistLayout`). Skin pixels =
    /// `floor(view / scale)` (the inverse of the integer nearest-neighbor upscale),
    /// then clamped to the minimum. A non-positive `scale` is treated as 1 so the
    /// arithmetic never traps; a tiny / negative view size clamps to the minimum.
    public static func skinSize(
        fromViewWidth viewWidth: Double,
        viewHeight: Double,
        scale: Int
    ) -> (width: Int, height: Int) {
        let s = Double(max(1, scale))
        let rawW = Int((viewWidth / s).rounded(.down))
        let rawH = Int((viewHeight / s).rounded(.down))
        return (
            width: max(rawW, minimumWidth),
            height: max(rawH, minimumHeight)
        )
    }

    // MARK: - Compose (public)

    /// Composite the resizable playlist window frame into a single RGBA8 bitmap at
    /// the target pixel size. Returns `nil` only when the `pledit.bmp` frame
    /// sprites are absent (no frame to draw). The requested `width`/`height` are
    /// clamped UP to `minimumWidth`/`minimumHeight` so the corners always fit; the
    /// returned bitmap's dimensions are the clamped size.
    ///
    /// `active` selects the focused (active) title strip vs the inactive one.
    public static func compose(
        _ skin: Skin,
        width: Int,
        height: Int,
        active: Bool = true
    ) -> DecodedBitmap? {
        // No frame sheet at all -> nothing to compose. (A single representative
        // corner sprite proves the sheet was cut; individual missing pieces below
        // are tolerated by `overlay`.)
        guard skin.sprite(sheet: sheet, name: "titleBarLeftCorner") != nil else {
            return nil
        }

        // Clamp to a sane minimum so the corners never overlap into a malformed
        // buffer. Never trust the caller to pass a workable size.
        let canvasWidth = max(width, minimumWidth)
        let canvasHeight = max(height, minimumHeight)

        // Start from a solid interior fill: the playlist normal background. The
        // track list will later draw over this. Fallback (black) keeps the frame
        // valid when `pledit.txt` carried no background colour.
        let background = skin.playlist?.normalBackground ?? RGBColor(r: 0, g: 0, b: 0)
        var canvas = solidCanvas(width: canvasWidth, height: canvasHeight, color: background)

        let titleH = titleBarHeight()
        let bottomH = bottomFrameHeight()

        // --- Side edges: tiled vertically down the body, between the title bar and
        // the bottom frame. Drawn FIRST so the corners/fills overdraw their tops
        // and bottoms cleanly. The body band is [titleH, canvasHeight - bottomH).
        let bodyTop = titleH
        let bodyBottom = canvasHeight - bottomH
        if let leftEdge = skin.sprite(sheet: sheet, name: "leftEdge") {
            tileVertically(leftEdge, onto: &canvas, x: 0, top: bodyTop, bottom: bodyBottom)
        }
        if let rightEdge = skin.sprite(sheet: sheet, name: "rightEdge") {
            let x = canvasWidth - rightEdge.width
            tileVertically(rightEdge, onto: &canvas, x: x, top: bodyTop, bottom: bodyBottom)
        }

        // --- Title bar across the top: left corner, tiled narrow texture, a
        // CENTERED title piece drawn ONCE, more tiled texture, right corner flush.
        // Active/inactive per `active`. The title must appear exactly once — the
        // texture (not the title) is what tiles, fixing the repeated-title bug.
        composeTitleBar(
            onto: &canvas,
            skin: skin,
            active: active,
            canvasWidth: canvasWidth
        )

        // --- Bottom frame flush to the bottom: bottom-left corner, tiled bottom
        // fill, bottom-right corner.
        composeBar(
            onto: &canvas,
            skin: skin,
            leftName: "bottomLeftCorner",
            fillName: "bottomFill",
            rightName: "bottomRightCorner",
            y: canvasHeight - bottomH,
            canvasWidth: canvasWidth
        )

        return canvas
    }

    // MARK: - Interior rect (public)

    /// The interior content rect — the area INSIDE the frame chrome where the
    /// track-list text is drawn — for a window of the given size, in the same
    /// top-left-origin pixel space as `compose`'s returned bitmap.
    ///
    /// The interior is bounded by the title-bar band on top, the bottom-frame
    /// band below, and the left/right edge sprites on the sides. The requested
    /// size is clamped UP to `minimumWidth`/`minimumHeight` first (matching
    /// `compose`), so the returned rect is always well-formed (`w`/`h` are clamped
    /// at 0, never negative). The harness shell uses this to know where — and how
    /// wide/tall — to draw the platform text, and feeds `h` to
    /// `PlaylistLayout.visibleRows` as the interior height.
    public static func interiorRect(width: Int, height: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        let canvasWidth = max(width, minimumWidth)
        let canvasHeight = max(height, minimumHeight)

        let leftInset = rect("leftEdge")?.width ?? 25
        let rightInset = rect("rightEdge")?.width ?? 20
        let topInset = titleBarHeight()
        let bottomInset = bottomFrameHeight()

        let x = leftInset
        let y = topInset
        let w = max(0, canvasWidth - leftInset - rightInset)
        let h = max(0, canvasHeight - topInset - bottomInset)
        return (x: x, y: y, w: w, h: h)
    }

    // MARK: - Title bar (corner | texture | centered title | texture | corner)

    /// Compose the title bar at row 0: the left corner at x=0, a CENTERED title
    /// piece drawn EXACTLY ONCE, and the narrow texture fill tiled on BOTH sides of
    /// the title to span the gaps between the corners and the title. The right
    /// corner is flush to the right edge. This is the fix for the repeated-title
    /// bug: it is the *texture* that tiles, never the title art.
    ///
    /// The title is centered in the full window width, then clamped so it never
    /// overlaps either corner. If the window is too narrow to seat the title
    /// between the corners at all, the title is SKIPPED and the texture simply
    /// tiles the whole inner gap (graceful, no overrun). Every piece is
    /// missing-tolerant (skipped if absent) and clipped to bounds by `overlay`.
    private static func composeTitleBar(
        onto canvas: inout DecodedBitmap,
        skin: Skin,
        active: Bool,
        canvasWidth: Int
    ) {
        let left = skin.sprite(sheet: sheet, name: "titleBarLeftCorner")
        let right = skin.sprite(sheet: sheet, name: "titleBarRightCorner")
        let fill = skin.sprite(sheet: sheet, name: active ? "titleBarFillActive" : "titleBarFillInactive")
        let title = skin.sprite(sheet: sheet, name: active ? "titleBarTitleActive" : "titleBarTitleInactive")

        let leftWidth = left?.width ?? 0
        let rightWidth = right?.width ?? 0
        // The inner gap between the two corners, where the title + texture live.
        let innerLeft = leftWidth
        let innerRight = canvasWidth - rightWidth

        // Center the title in the FULL window width, then clamp into the inner gap
        // so it never overlaps a corner. If it cannot fit between the corners, drop
        // it and let the texture fill the whole gap.
        var titleLeft: Int?
        if let title, title.width <= innerRight - innerLeft {
            var x = (canvasWidth - title.width) / 2
            x = max(innerLeft, min(x, innerRight - title.width))
            titleLeft = x
        }

        // Texture tiles the gaps on each side of the title (or the whole inner gap
        // when the title is absent). Drawn FIRST so the corners and the title piece
        // overdraw any tile that clipped into their columns.
        if let fill {
            if let titleLeft, let title {
                tileHorizontally(fill, onto: &canvas, left: innerLeft, right: titleLeft, y: 0)
                tileHorizontally(fill, onto: &canvas, left: titleLeft + title.width, right: innerRight, y: 0)
            } else {
                tileHorizontally(fill, onto: &canvas, left: innerLeft, right: innerRight, y: 0)
            }
        }

        // The title piece, drawn ONCE, centered (clamped). Over the texture, under
        // the corners.
        if let title, let titleLeft {
            SkinCanvas.overlay(title, onto: &canvas, x: titleLeft, y: 0)
        }

        // Corners last so they win over any tile/title that clipped into them.
        if let left {
            SkinCanvas.overlay(left, onto: &canvas, x: 0, y: 0)
        }
        if let right {
            SkinCanvas.overlay(right, onto: &canvas, x: canvasWidth - right.width, y: 0)
        }
    }

    // MARK: - Bar (corner | tiled fill | corner)

    /// Compose one horizontal bar at row `y`: the left corner at x=0, the centre
    /// fill tiled across the gap, and the right corner flush to the right edge.
    /// Every piece is missing-tolerant (skipped if absent) and clipped to bounds
    /// by `overlay`. The right corner is drawn LAST so it wins over any fill tile
    /// that clipped into its column.
    private static func composeBar(
        onto canvas: inout DecodedBitmap,
        skin: Skin,
        leftName: String,
        fillName: String,
        rightName: String,
        y: Int,
        canvasWidth: Int
    ) {
        let left = skin.sprite(sheet: sheet, name: leftName)
        let right = skin.sprite(sheet: sheet, name: rightName)
        let leftWidth = left?.width ?? 0
        let rightWidth = right?.width ?? 0

        // Tiled centre fill spans the gap between the two corners. Drawn first so
        // the corners overdraw any tile that clipped into their columns.
        if let fill = skin.sprite(sheet: sheet, name: fillName) {
            tileHorizontally(
                fill, onto: &canvas,
                left: leftWidth,
                right: canvasWidth - rightWidth,
                y: y
            )
        }

        if let left {
            SkinCanvas.overlay(left, onto: &canvas, x: 0, y: y)
        }
        if let right {
            SkinCanvas.overlay(right, onto: &canvas, x: canvasWidth - right.width, y: y)
        }
    }

    // MARK: - Tiling primitives

    /// Tile `sprite` horizontally, top at `y`, filling the column range
    /// `[left, right)`. The last tile is clipped by `overlay` when it would
    /// overrun `right` (and the canvas), so a non-exact multiple never overruns.
    /// A zero/negative gap or a zero-width sprite is a no-op.
    private static func tileHorizontally(
        _ sprite: DecodedBitmap,
        onto canvas: inout DecodedBitmap,
        left: Int,
        right: Int,
        y: Int
    ) {
        guard sprite.width > 0, right > left else { return }
        var x = left
        while x < right {
            // Clamp the visible width of this tile to the remaining gap so a tile
            // never paints past `right` into the (later-drawn) corner column.
            let remaining = right - x
            if remaining >= sprite.width {
                SkinCanvas.overlay(sprite, onto: &canvas, x: x, y: y)
            } else {
                SkinCanvas.overlay(croppedWidth(sprite, to: remaining), onto: &canvas, x: x, y: y)
            }
            x += sprite.width
        }
    }

    /// Tile `sprite` vertically, left at `x`, filling the row range
    /// `[top, bottom)`. The last tile is clipped when it would overrun `bottom`.
    /// A zero/negative span or a zero-height sprite is a no-op.
    private static func tileVertically(
        _ sprite: DecodedBitmap,
        onto canvas: inout DecodedBitmap,
        x: Int,
        top: Int,
        bottom: Int
    ) {
        guard sprite.height > 0, bottom > top else { return }
        var y = top
        while y < bottom {
            let remaining = bottom - y
            if remaining >= sprite.height {
                SkinCanvas.overlay(sprite, onto: &canvas, x: x, y: y)
            } else {
                SkinCanvas.overlay(croppedHeight(sprite, to: remaining), onto: &canvas, x: x, y: y)
            }
            y += sprite.height
        }
    }

    // MARK: - Sprite cropping (last-tile clipping)
    //
    // `overlay` already clips a sprite to the CANVAS bounds, but a tiled fill must
    // also stop at the OPPOSITE corner / band boundary, which is generally inside
    // the canvas. Cropping the final tile's width/height to the remaining gap is
    // how the fill stops cleanly there. A malformed (size-inconsistent) sprite, or
    // a non-positive crop, yields an empty bitmap that `overlay` then skips.

    /// A copy of `sprite` with its width reduced to `newWidth` columns (top-left
    /// retained). Returns the original when `newWidth >= sprite.width`.
    private static func croppedWidth(_ sprite: DecodedBitmap, to newWidth: Int) -> DecodedBitmap {
        guard newWidth < sprite.width else { return sprite }
        guard newWidth > 0,
              sprite.pixels.count == sprite.width * sprite.height * 4 else {
            return DecodedBitmap(width: 0, height: 0, pixels: [])
        }
        var pixels = [UInt8]()
        pixels.reserveCapacity(newWidth * sprite.height * 4)
        for row in 0..<sprite.height {
            let rowStart = row * sprite.width * 4
            pixels.append(contentsOf: sprite.pixels[rowStart..<(rowStart + newWidth * 4)])
        }
        return DecodedBitmap(width: newWidth, height: sprite.height, pixels: pixels)
    }

    /// A copy of `sprite` with its height reduced to `newHeight` rows (top
    /// retained). Returns the original when `newHeight >= sprite.height`.
    private static func croppedHeight(_ sprite: DecodedBitmap, to newHeight: Int) -> DecodedBitmap {
        guard newHeight < sprite.height else { return sprite }
        guard newHeight > 0,
              sprite.pixels.count == sprite.width * sprite.height * 4 else {
            return DecodedBitmap(width: 0, height: 0, pixels: [])
        }
        let byteCount = newHeight * sprite.width * 4
        return DecodedBitmap(
            width: sprite.width,
            height: newHeight,
            pixels: Array(sprite.pixels[0..<byteCount])
        )
    }

    // MARK: - Solid fill

    /// A solid RGBA8 canvas of the given size, every pixel set to `color` (opaque).
    private static func solidCanvas(width: Int, height: Int, color: RGBColor) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.r
            pixels[index + 1] = color.g
            pixels[index + 2] = color.b
            pixels[index + 3] = 255
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    // MARK: - Sprite-geometry lookups
    //
    // The composer reads band heights and corner widths from `SpriteCoordinates`
    // (the single source of truth for the sheet's packing) so the layout follows
    // the sprite table rather than duplicating its numbers. Each lookup falls back
    // to the documented nominal if the rect is somehow absent, so the geometry is
    // always well-formed.

    private static func rect(_ name: String) -> SpriteRect? {
        SpriteCoordinates.playlistWindow[sheet]?.first { $0.name == name }
    }

    private static func titleBarHeight() -> Int {
        rect("titleBarLeftCorner")?.height ?? 20
    }

    private static func bottomFrameHeight() -> Int {
        rect("bottomLeftCorner")?.height ?? 38
    }

    private static func titleCornerWidths() -> (left: Int, right: Int) {
        (rect("titleBarLeftCorner")?.width ?? 25, rect("titleBarRightCorner")?.width ?? 25)
    }

    private static func bottomCornerWidths() -> (left: Int, right: Int) {
        (rect("bottomLeftCorner")?.width ?? 125, rect("bottomRightCorner")?.width ?? 125)
    }
}
