import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure RGBA8 playlist-window FRAME compositor on synthetic skins
/// built entirely in-memory (no real `.wsz` files, no graphics framework). The
/// playlist frame is tiled chrome (corners + tiled fills + tiled edges) sized to
/// an arbitrary window width/height, so these tests assert directly on the
/// returned `DecodedBitmap.pixels`: the result dimensions, the four corners
/// landing at the four corners, the title fill tiling horizontally, the interior
/// equal to the playlist normal background, buffer-length consistency (no
/// out-of-range write), the missing-sheet -> nil contract, and the below-minimum
/// clamp (never traps).
final class PlaylistWindowComposerTests: XCTestCase {

    // MARK: - Helpers

    /// A solid-color RGBA8 bitmap of the given size, every pixel set to `color`.
    private func solidBitmap(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8, UInt8)
    ) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = color.3
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    /// The RGBA tuple at `(x, y)` in a bitmap, read straight from the buffer.
    private func pixel(_ bitmap: DecodedBitmap, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * bitmap.width + x) * 4
        return (
            bitmap.pixels[index],
            bitmap.pixels[index + 1],
            bitmap.pixels[index + 2],
            bitmap.pixels[index + 3]
        )
    }

    /// Builds a synthetic `pledit.bmp` sprite set where each frame sprite is a
    /// distinct solid color at its NOMINAL size (from `SpriteCoordinates`), so a
    /// composed pixel can be matched back to the exact source sprite. The optional
    /// `playlist` colors drive the interior fill.
    private func makeSkin(
        colors: [String: (UInt8, UInt8, UInt8, UInt8)] = [:],
        playlist: PlaylistColors? = nil,
        omit: Set<String> = []
    ) -> Skin {
        guard let rects = SpriteCoordinates.playlistWindow["pledit.bmp"] else {
            fatalError("pledit.bmp coordinates missing from SpriteCoordinates")
        }
        var sheet: [String: DecodedBitmap] = [:]
        for rect in rects where !omit.contains(rect.name) {
            let color = colors[rect.name] ?? (128, 128, 128, 255)
            sheet[rect.name] = solidBitmap(width: rect.width, height: rect.height, color: color)
        }
        return Skin(
            sprites: ["pledit.bmp": sheet],
            visColors: [],
            playlist: playlist,
            region: nil
        )
    }

    /// The nominal size of a named `pledit.bmp` sprite, from `SpriteCoordinates`.
    private func nominalSize(_ name: String) -> (width: Int, height: Int) {
        let rect = SpriteCoordinates.playlistWindow["pledit.bmp"]!.first { $0.name == name }!
        return (rect.width, rect.height)
    }

    private let normalBG = PlaylistColors(
        normalText: nil,
        currentText: nil,
        normalBackground: RGBColor(r: 11, g: 22, b: 33),
        selectedBackground: nil,
        font: nil
    )

    // MARK: - 1. Composes at the minimum size with correct dimensions

    func testComposesAtMinimumSizeWithExactDimensions() {
        let minW = PlaylistWindowComposer.minimumWidth
        let minH = PlaylistWindowComposer.minimumHeight
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(playlist: normalBG), width: minW, height: minH
        ) else {
            XCTFail("compose returned nil at minimum size")
            return
        }
        XCTAssertEqual(composed.width, minW)
        XCTAssertEqual(composed.height, minH)
        // Buffer length is exactly width*height*4 — no pixel written out of range.
        XCTAssertEqual(composed.pixels.count, minW * minH * 4)
    }

    // MARK: - 2. Composes at a larger size; corners land at the four corners

    func testCornersLandAtTheFourCornersAtLargerSize() {
        let width = 350
        let height = 250
        let cornerColors: [String: (UInt8, UInt8, UInt8, UInt8)] = [
            "titleBarLeftCorner": (255, 0, 0, 255),
            "titleBarRightCorner": (0, 255, 0, 255),
            "bottomLeftCorner": (0, 0, 255, 255),
            "bottomRightCorner": (255, 255, 0, 255)
        ]
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(colors: cornerColors, playlist: normalBG),
            width: width, height: height
        ) else {
            XCTFail("compose returned nil at larger size")
            return
        }
        XCTAssertEqual(composed.width, width)
        XCTAssertEqual(composed.height, height)
        XCTAssertEqual(composed.pixels.count, width * height * 4)

        // Top-left corner pixel == titleBarLeftCorner color.
        XCTAssertEqual(pixel(composed, x: 0, y: 0).0, 255)
        XCTAssertEqual(pixel(composed, x: 0, y: 0).1, 0)

        // Top-right corner pixel == titleBarRightCorner color. The right corner is
        // flush to the right edge, so its top-right-most pixel is at (width-1, 0).
        XCTAssertEqual(pixel(composed, x: width - 1, y: 0).1, 255)
        XCTAssertEqual(pixel(composed, x: width - 1, y: 0).0, 0)

        // Bottom-left corner pixel == bottomLeftCorner color. The bottom frame is
        // flush to the bottom; its bottom-left-most pixel is at (0, height-1).
        XCTAssertEqual(pixel(composed, x: 0, y: height - 1).2, 255)

        // Bottom-right corner pixel == bottomRightCorner color, at (width-1, height-1).
        let br = pixel(composed, x: width - 1, y: height - 1)
        XCTAssertEqual(br.0, 255)
        XCTAssertEqual(br.1, 255)
        XCTAssertEqual(br.2, 0)
    }

    // MARK: - 3. Title texture fill tiles on BOTH sides of the centered title

    func testTitleFillTilesOnBothSidesOfTheTitle() {
        let width = 350
        let height = 250
        let fillColor: (UInt8, UInt8, UInt8, UInt8) = (3, 7, 9, 255)
        // A distinct title color so we can locate the (single) title block and
        // assert the FILL texture flanks it on both sides.
        let titleColor: (UInt8, UInt8, UInt8, UInt8) = (200, 50, 150, 255)
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(
                colors: ["titleBarFillActive": fillColor, "titleBarTitleActive": titleColor],
                playlist: normalBG
            ),
            width: width, height: height
        ) else {
            XCTFail("compose returned nil")
            return
        }
        let leftCorner = nominalSize("titleBarLeftCorner")
        let rightCorner = nominalSize("titleBarRightCorner")
        let title = nominalSize("titleBarTitleActive")
        let titleRowY = min(leftCorner.height, 2)

        // The title is centered in the full window; compute its clamped left edge.
        let innerLeft = leftCorner.width
        let innerRight = width - rightCorner.width
        var titleLeft = (width - title.width) / 2
        titleLeft = max(innerLeft, min(titleLeft, innerRight - title.width))
        let titleRight = titleLeft + title.width

        // Just LEFT of the title and just RIGHT of the title must be the FILL
        // texture (proving the texture tiles both sides), not the title color.
        let leftSampleX = (innerLeft + titleLeft) / 2
        let rightSampleX = (titleRight + innerRight) / 2
        XCTAssertLessThan(innerLeft, titleLeft, "test needs a left-side fill gap")
        XCTAssertLessThan(titleRight, innerRight, "test needs a right-side fill gap")

        let leftPx = pixel(composed, x: leftSampleX, y: titleRowY)
        XCTAssertEqual(leftPx.0, fillColor.0, "left of title should be fill texture")
        XCTAssertEqual(leftPx.1, fillColor.1)
        XCTAssertEqual(leftPx.2, fillColor.2)

        let rightPx = pixel(composed, x: rightSampleX, y: titleRowY)
        XCTAssertEqual(rightPx.0, fillColor.0, "right of title should be fill texture")
        XCTAssertEqual(rightPx.1, fillColor.1)
        XCTAssertEqual(rightPx.2, fillColor.2)
    }

    // MARK: - 3b. Title is drawn EXACTLY ONCE, centered (not tiled/repeated)

    func testTitleDrawnOnceCenteredNotRepeated() {
        let width = 350
        let height = 250
        let fillColor: (UInt8, UInt8, UInt8, UInt8) = (3, 7, 9, 255)
        let titleColor: (UInt8, UInt8, UInt8, UInt8) = (200, 50, 150, 255)
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(
                colors: ["titleBarFillActive": fillColor, "titleBarTitleActive": titleColor],
                playlist: normalBG
            ),
            width: width, height: height
        ) else {
            XCTFail("compose returned nil")
            return
        }
        let leftCorner = nominalSize("titleBarLeftCorner")
        let rightCorner = nominalSize("titleBarRightCorner")
        let title = nominalSize("titleBarTitleActive")
        let titleRowY = min(leftCorner.height, 2)

        let innerLeft = leftCorner.width
        let innerRight = width - rightCorner.width
        var titleLeft = (width - title.width) / 2
        titleLeft = max(innerLeft, min(titleLeft, innerRight - title.width))

        // Count, across the whole title row, the maximal run-length of contiguous
        // title-colored columns. With the title drawn ONCE its run is ~title.width;
        // the OLD tiled-title bug would smear the title color across the whole gap
        // (run >> title.width) or repeat it in disjoint runs.
        func isTitle(_ x: Int) -> Bool {
            let p = pixel(composed, x: x, y: titleRowY)
            return p.0 == titleColor.0 && p.1 == titleColor.1 && p.2 == titleColor.2
        }
        var runs: [Int] = []
        var run = 0
        for x in 0..<width {
            if isTitle(x) { run += 1 } else if run > 0 { runs.append(run); run = 0 }
        }
        if run > 0 { runs.append(run) }

        // Exactly ONE contiguous title run, and its width equals the title sprite.
        XCTAssertEqual(runs.count, 1, "title must appear exactly once, got runs=\(runs)")
        XCTAssertEqual(runs.first, title.width, "the single title run must be the title's width")

        // The centre of the window is inside the title; near the corners is NOT.
        XCTAssertTrue(isTitle(width / 2), "title should cover the window centre")
        XCTAssertFalse(isTitle(innerLeft + 1), "no title near the left corner (should be fill)")
        XCTAssertFalse(isTitle(innerRight - 2), "no title near the right corner (should be fill)")
        // And the title is centered: its left edge is the clamped center position.
        XCTAssertTrue(isTitle(titleLeft), "title starts at its centered left edge")
        XCTAssertFalse(isTitle(titleLeft - 1), "fill (not title) immediately left of the title")
    }

    // MARK: - 4. Interior centre pixel == normalBG

    func testInteriorCentrePixelEqualsNormalBackground() {
        let width = 350
        let height = 250
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(playlist: normalBG), width: width, height: height
        ) else {
            XCTFail("compose returned nil")
            return
        }
        let centre = pixel(composed, x: width / 2, y: height / 2)
        XCTAssertEqual(centre.0, 11)
        XCTAssertEqual(centre.1, 22)
        XCTAssertEqual(centre.2, 33)
        XCTAssertEqual(centre.3, 255)
    }

    // MARK: - 5. Active vs inactive title sprites

    func testInactiveUsesInactiveTitleSprite() {
        let width = 350
        let height = 250
        // Distinct colors for active vs inactive title fill AND title so we can
        // confirm the `active:` flag selects the right strip for both pieces.
        let colors: [String: (UInt8, UInt8, UInt8, UInt8)] = [
            "titleBarFillActive": (100, 0, 0, 255),
            "titleBarFillInactive": (0, 100, 0, 255),
            "titleBarTitleActive": (101, 0, 0, 255),
            "titleBarTitleInactive": (0, 101, 0, 255)
        ]
        let leftCorner = nominalSize("titleBarLeftCorner")
        let titleRowY = min(leftCorner.height, 2)
        // A point in the left-side fill texture (just right of the left corner).
        let fillSampleX = leftCorner.width + 1
        // The window centre lands inside the (single, centered) title piece.
        let titleSampleX = width / 2

        guard let inactive = PlaylistWindowComposer.compose(
            makeSkin(colors: colors, playlist: normalBG),
            width: width, height: height, active: false
        ) else {
            XCTFail("compose(active:false) returned nil")
            return
        }
        let fillPx = pixel(inactive, x: fillSampleX, y: titleRowY)
        XCTAssertEqual(fillPx.1, 100, "inactive compose should use the inactive title fill")
        XCTAssertEqual(fillPx.0, 0)
        let titlePx = pixel(inactive, x: titleSampleX, y: titleRowY)
        XCTAssertEqual(titlePx.1, 101, "inactive compose should use the inactive title piece")
        XCTAssertEqual(titlePx.0, 0)

        // And active selects the active title piece.
        guard let active = PlaylistWindowComposer.compose(
            makeSkin(colors: colors, playlist: normalBG),
            width: width, height: height, active: true
        ) else {
            XCTFail("compose(active:true) returned nil")
            return
        }
        let activeTitle = pixel(active, x: titleSampleX, y: titleRowY)
        XCTAssertEqual(activeTitle.0, 101, "active compose should use the active title piece")
        XCTAssertEqual(activeTitle.1, 0)
    }

    // MARK: - 6. Missing pledit.bmp -> nil

    func testMissingPleditSheetReturnsNil() {
        let skin = Skin(sprites: [:], visColors: [], playlist: normalBG, region: nil)
        XCTAssertNil(PlaylistWindowComposer.compose(skin, width: 300, height: 200))
    }

    // MARK: - 7. Below-minimum width clamps without trapping

    func testBelowMinimumSizeClampsWithoutTrapping() {
        // Ask for a width/height far below the corner sums. The compositor must
        // clamp to the minimum (not trap, not overrun the buffer).
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(playlist: normalBG), width: 1, height: 1
        ) else {
            XCTFail("compose returned nil for a below-minimum request")
            return
        }
        XCTAssertGreaterThanOrEqual(composed.width, PlaylistWindowComposer.minimumWidth)
        XCTAssertGreaterThanOrEqual(composed.height, PlaylistWindowComposer.minimumHeight)
        // Whatever it clamped to, the buffer is exactly consistent.
        XCTAssertEqual(composed.pixels.count, composed.width * composed.height * 4)
    }

    // MARK: - 8. Buffer length invariant at an odd (non-multiple) size

    func testBufferLengthInvariantAtNonMultipleSize() {
        // A deliberately awkward size (not a multiple of any tile) to exercise the
        // last-tile clipping on every tiled axis. The buffer must still be exactly
        // width*height*4 with no out-of-range write.
        let width = 333
        let height = 207
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(playlist: normalBG), width: width, height: height
        ) else {
            XCTFail("compose returned nil")
            return
        }
        XCTAssertEqual(composed.width, width)
        XCTAssertEqual(composed.height, height)
        XCTAssertEqual(composed.pixels.count, width * height * 4)
    }

    // MARK: - 9. Nil playlist colors still composes (interior falls back)

    func testNilPlaylistColorsStillComposes() {
        // No playlist colors at all: the compositor must still produce a valid
        // frame (interior uses a documented fallback) rather than nil/trap.
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(playlist: nil), width: 300, height: 200
        ) else {
            XCTFail("compose returned nil with nil playlist colors")
            return
        }
        XCTAssertEqual(composed.pixels.count, 300 * 200 * 4)
    }

    // MARK: - 10. Title appears once at a WIDER width too (no extra copies)

    func testTitleStillDrawnOnceAtWideWidth() {
        let width = 520
        let height = 250
        let titleColor: (UInt8, UInt8, UInt8, UInt8) = (200, 50, 150, 255)
        let fillColor: (UInt8, UInt8, UInt8, UInt8) = (3, 7, 9, 255)
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(
                colors: ["titleBarTitleActive": titleColor, "titleBarFillActive": fillColor],
                playlist: normalBG
            ),
            width: width, height: height
        ) else {
            XCTFail("compose returned nil at wide width")
            return
        }
        let leftCorner = nominalSize("titleBarLeftCorner")
        let title = nominalSize("titleBarTitleActive")
        let titleRowY = min(leftCorner.height, 2)
        func isTitle(_ x: Int) -> Bool {
            let p = pixel(composed, x: x, y: titleRowY)
            return p.0 == titleColor.0 && p.1 == titleColor.1 && p.2 == titleColor.2
        }
        var titleColumns = 0
        var runs = 0
        var inRun = false
        for x in 0..<width {
            if isTitle(x) {
                titleColumns += 1
                if !inRun { runs += 1; inRun = true }
            } else {
                inRun = false
            }
        }
        // Even at a much wider window, the title is drawn exactly once: one run,
        // total title columns == one title width (not 2x/3x like the tiled bug).
        XCTAssertEqual(runs, 1, "title must be a single run at wide width")
        XCTAssertEqual(titleColumns, title.width, "exactly one title's worth of columns")
        XCTAssertTrue(isTitle(width / 2), "the single title is centered at wide width")
    }

    // MARK: - 11. Too-narrow window: title is skipped gracefully (no overrun)

    func testNarrowWidthSkipsTitleGracefully() {
        // A width where the corners + a sliver of gap fit, but the 100px title
        // cannot be seated between the corners. The title must be SKIPPED (texture
        // fills the gap) and the buffer must remain exactly consistent — no trap,
        // no out-of-range write.
        let leftCorner = nominalSize("titleBarLeftCorner")
        let rightCorner = nominalSize("titleBarRightCorner")
        let title = nominalSize("titleBarTitleActive")
        // Just wide enough for both corners plus a few fill pixels, but far narrower
        // than corners + title.
        let width = leftCorner.width + rightCorner.width + 6
        XCTAssertLessThan(
            width, leftCorner.width + rightCorner.width + title.width,
            "test width must be too narrow for the title")
        let height = 200

        let titleColor: (UInt8, UInt8, UInt8, UInt8) = (200, 50, 150, 255)
        let fillColor: (UInt8, UInt8, UInt8, UInt8) = (3, 7, 9, 255)
        guard let composed = PlaylistWindowComposer.compose(
            makeSkin(
                colors: ["titleBarTitleActive": titleColor, "titleBarFillActive": fillColor],
                playlist: normalBG
            ),
            width: width, height: height
        ) else {
            XCTFail("compose returned nil at narrow width")
            return
        }
        // Clamp may bump width up to minimumWidth; whatever it is, the buffer is
        // exactly consistent (the core no-overrun guarantee).
        XCTAssertEqual(composed.pixels.count, composed.width * composed.height * 4)

        // The title color must NOT appear anywhere in the title row when it can't
        // fit (graceful skip, not a clipped half-title smeared in).
        let titleRowY = min(leftCorner.height, 2)
        if composed.width < leftCorner.width + rightCorner.width + title.width {
            var sawTitle = false
            for x in 0..<composed.width {
                let p = pixel(composed, x: x, y: titleRowY)
                if p.0 == titleColor.0 && p.1 == titleColor.1 && p.2 == titleColor.2 {
                    sawTitle = true; break
                }
            }
            XCTAssertFalse(sawTitle, "title must be skipped when it cannot fit between corners")
        }
    }
}
