import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure visible-rows arithmetic for the classic playlist track
/// list: the clamped scroll window (`PlaylistLayout.visibleRows`), the
/// rows-that-fit / max-scroll primitives, and the frame interior rect
/// (`PlaylistWindowComposer.interiorRect`). All Foundation-only — no AppKit, no
/// real skin, no bitmaps.
final class PlaylistLayoutTests: XCTestCase {

    // MARK: - rowsThatFit (round UP so a partial last row counts)

    func testRowsThatFitExactMultiple() {
        XCTAssertEqual(PlaylistLayout.rowsThatFit(interiorHeight: 100, rowHeight: 10), 10)
    }

    func testRowsThatFitRoundsUpForPartialLastRow() {
        // 105 / 10 -> 11 rows (the 11th is only half visible but still drawn).
        XCTAssertEqual(PlaylistLayout.rowsThatFit(interiorHeight: 105, rowHeight: 10), 11)
    }

    func testRowsThatFitNonPositiveInputsAreZero() {
        XCTAssertEqual(PlaylistLayout.rowsThatFit(interiorHeight: 0, rowHeight: 10), 0)
        XCTAssertEqual(PlaylistLayout.rowsThatFit(interiorHeight: 100, rowHeight: 0), 0)
        XCTAssertEqual(PlaylistLayout.rowsThatFit(interiorHeight: -50, rowHeight: 10), 0)
        XCTAssertEqual(PlaylistLayout.rowsThatFit(interiorHeight: 100, rowHeight: -10), 0)
    }

    // MARK: - maxScrollRow (uses WHOLE rows that fit; clamp leaves list filled)

    func testMaxScrollRowAllTracksFitIsZero() {
        // 5 tracks, 10 whole rows fit -> nothing to scroll.
        XCTAssertEqual(
            PlaylistLayout.maxScrollRow(trackCount: 5, interiorHeight: 100, rowHeight: 10),
            0
        )
    }

    func testMaxScrollRowMoreTracksThanFit() {
        // 30 tracks, 10 whole rows fit -> max scroll leaves the last 10 filling
        // the interior: 30 - 10 = 20.
        XCTAssertEqual(
            PlaylistLayout.maxScrollRow(trackCount: 30, interiorHeight: 100, rowHeight: 10),
            20
        )
    }

    func testMaxScrollRowUsesFloorOfWholeRows() {
        // 105px / 10px -> 10 WHOLE rows fit (the 11th is partial). 30 - 10 = 20,
        // so the clamp does NOT over-scroll on the partial row.
        XCTAssertEqual(
            PlaylistLayout.maxScrollRow(trackCount: 30, interiorHeight: 105, rowHeight: 10),
            20
        )
    }

    func testMaxScrollRowDegenerateGeometryIsZero() {
        XCTAssertEqual(PlaylistLayout.maxScrollRow(trackCount: 30, interiorHeight: 0, rowHeight: 10), 0)
        XCTAssertEqual(PlaylistLayout.maxScrollRow(trackCount: 30, interiorHeight: 100, rowHeight: 0), 0)
        XCTAssertEqual(PlaylistLayout.maxScrollRow(trackCount: 0, interiorHeight: 100, rowHeight: 10), 0)
    }

    // MARK: - visibleRows: fewer tracks than fit (no scroll)

    func testVisibleRowsFewerTracksThanFit() {
        // 4 tracks, room for 10 -> all 4 visible, no scroll possible.
        let v = PlaylistLayout.visibleRows(
            trackCount: 4, scrollRow: 0, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 0)
        XCTAssertEqual(v.lastVisible, 4)
        XCTAssertEqual(v.scrollRow, 0)
        XCTAssertEqual(v.count, 4)
    }

    func testVisibleRowsFewerTracksThanFitIgnoresPositiveScroll() {
        // Asking to scroll when everything fits clamps back to 0.
        let v = PlaylistLayout.visibleRows(
            trackCount: 4, scrollRow: 3, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 0)
        XCTAssertEqual(v.lastVisible, 4)
        XCTAssertEqual(v.scrollRow, 0)
    }

    // MARK: - visibleRows: scroll < 0 clamps to top

    func testVisibleRowsNegativeScrollClampsToTop() {
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: -7, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 0)
        XCTAssertEqual(v.lastVisible, 10) // 10 rows fit
        XCTAssertEqual(v.scrollRow, 0)
    }

    // MARK: - visibleRows: scroll > max clamps to bottom

    func testVisibleRowsOverScrollClampsToBottom() {
        // 30 tracks, 10 fit, max scroll 20. Ask for 100 -> clamp to 20; the
        // visible window is rows 20..<30 (the last 10).
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 100, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.scrollRow, 20)
        XCTAssertEqual(v.firstVisible, 20)
        XCTAssertEqual(v.lastVisible, 30)
        XCTAssertEqual(v.count, 10)
    }

    // MARK: - visibleRows: mid-scroll window

    func testVisibleRowsMidScrollWindow() {
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 5, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 5)
        XCTAssertEqual(v.lastVisible, 15)
        XCTAssertEqual(v.scrollRow, 5)
        XCTAssertEqual(v.count, 10)
    }

    // MARK: - visibleRows: partial last row counts as visible

    func testVisibleRowsPartialLastRowIsVisible() {
        // 105px interior, 10px rows -> 11 rows reported (the 11th partial).
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 0, interiorHeight: 105, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 0)
        XCTAssertEqual(v.lastVisible, 11, "partial 11th row should still be reported visible")
    }

    func testVisibleRowsPartialRowAtBottomClampDoesNotOverrun() {
        // At the bottom clamp the visible window must not run past trackCount even
        // with a partial row in play.
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 999, interiorHeight: 105, rowHeight: 10
        )
        // Whole rows that fit = 10, so max scroll = 20; window is 20..<min(20+11,30)=30.
        XCTAssertEqual(v.scrollRow, 20)
        XCTAssertEqual(v.firstVisible, 20)
        XCTAssertEqual(v.lastVisible, 30)
    }

    // MARK: - visibleRows: empty list

    func testVisibleRowsEmptyList() {
        let v = PlaylistLayout.visibleRows(
            trackCount: 0, scrollRow: 0, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 0)
        XCTAssertEqual(v.lastVisible, 0)
        XCTAssertEqual(v.count, 0)
        XCTAssertEqual(v.scrollRow, 0)
    }

    func testVisibleRowsNegativeTrackCountTreatedAsEmpty() {
        let v = PlaylistLayout.visibleRows(
            trackCount: -5, scrollRow: 2, interiorHeight: 100, rowHeight: 10
        )
        XCTAssertEqual(v.firstVisible, 0)
        XCTAssertEqual(v.lastVisible, 0)
        XCTAssertEqual(v.scrollRow, 0)
    }

    // MARK: - visibleRows: degenerate geometry yields no rows (no trap)

    func testVisibleRowsZeroInteriorHeightYieldsNoRows() {
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 5, interiorHeight: 0, rowHeight: 10
        )
        XCTAssertEqual(v.count, 0)
        XCTAssertEqual(v.scrollRow, 0)
    }

    func testVisibleRowsZeroRowHeightYieldsNoRows() {
        // Guards the divide-by-zero in rowsThatFit / maxScrollRow.
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 5, interiorHeight: 100, rowHeight: 0
        )
        XCTAssertEqual(v.count, 0)
        XCTAssertEqual(v.scrollRow, 0)
    }

    func testVisibleRowsNegativeRowHeightYieldsNoRows() {
        let v = PlaylistLayout.visibleRows(
            trackCount: 30, scrollRow: 5, interiorHeight: 100, rowHeight: -10
        )
        XCTAssertEqual(v.count, 0)
    }

    // MARK: - interiorRect: inside the frame chrome, well-formed

    func testInteriorRectInsetByFrameChrome() {
        // pledit frame: title bar h=20, bottom h=38, left edge w=25, right edge w=20.
        let r = PlaylistWindowComposer.interiorRect(width: 350, height: 250)
        XCTAssertEqual(r.x, 25)
        XCTAssertEqual(r.y, 20)
        XCTAssertEqual(r.w, 350 - 25 - 20)
        XCTAssertEqual(r.h, 250 - 20 - 38)
    }

    func testInteriorRectClampsBelowMinimumWithoutNegativeSize() {
        // Below-minimum request: interiorRect clamps the canvas up like compose,
        // so w/h are never negative.
        let r = PlaylistWindowComposer.interiorRect(width: 1, height: 1)
        XCTAssertGreaterThanOrEqual(r.w, 0)
        XCTAssertGreaterThanOrEqual(r.h, 0)
        // The interior origin still sits below the title bar and right of the left edge.
        XCTAssertEqual(r.x, 25)
        XCTAssertEqual(r.y, 20)
    }

    func testInteriorRectMatchesComposeClampedSize() {
        // The interior width + side insets should equal the clamped canvas width,
        // and similarly for height — i.e. the rect tiles the composed bitmap.
        let composed = PlaylistWindowComposer.compose(
            makeFrameSkin(), width: 400, height: 300
        )
        let r = PlaylistWindowComposer.interiorRect(width: 400, height: 300)
        XCTAssertNotNil(composed)
        if let composed {
            XCTAssertEqual(r.x + r.w + 20, composed.width) // 20 = right edge width
            XCTAssertEqual(r.y + r.h + 38, composed.height) // 38 = bottom frame height
        }
    }

    // MARK: - Helpers

    /// A synthetic pledit frame skin (solid sprites at nominal sizes) so compose
    /// succeeds for the interiorRect cross-check.
    private func makeFrameSkin() -> Skin {
        guard let rects = SpriteCoordinates.playlistWindow["pledit.bmp"] else {
            fatalError("pledit.bmp coordinates missing")
        }
        var sheet: [String: DecodedBitmap] = [:]
        for rect in rects {
            let pixels = [UInt8](repeating: 128, count: rect.width * rect.height * 4)
            sheet[rect.name] = DecodedBitmap(width: rect.width, height: rect.height, pixels: pixels)
        }
        return Skin(sprites: ["pledit.bmp": sheet], visColors: [], playlist: nil, region: nil)
    }
}
