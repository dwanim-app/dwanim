import Foundation
import XCTest
@testable import SkinKit

/// Permanent guard that every sprite rectangle in the main-window table fits
/// within the **real** measured sheet dimensions. These standard dimensions were
/// measured across a large corpus of real classic `.wsz` skins; where a sheet
/// size varied between skins, the SMALLER value is used here so that any rect
/// fitting this table is guaranteed to fit every observed skin.
///
/// This is pure arithmetic — it does not read any real skin file. It exists so
/// that a future edit to `SpriteCoordinates` cannot reintroduce an over-bounds
/// rectangle without a test failing.
final class SpriteCoordinatesFitTests: XCTestCase {

    /// Standard (smallest observed) sheet dimensions, in pixels: sheet filename
    /// -> (width, height). A rect on a sheet must satisfy
    /// `x >= 0, y >= 0, x + width <= STD_WIDTH, y + height <= STD_HEIGHT`.
    private static let standardDimensions: [String: (width: Int, height: Int)] = [
        "main.bmp":     (275, 116),
        "cbuttons.bmp": (136, 36),
        "titlebar.bmp": (344, 87),
        "shufrep.bmp":  (92, 85),
        // posbar's canonical/modal sheet is 307x10. A minority of skins ship it
        // as a short strip (2-9px tall) that intentionally omits the thumb, or
        // 248px wide (track only); those are not chased here — the canonical
        // 307x10 keeps the ~96.5% modal majority correct.
        "posbar.bmp":   (307, 10),
        "numbers.bmp":  (99, 13),
        "monoster.bmp": (58, 24),
        "playpaus.bmp": (42, 9),
        // volume's nominal content height is 420 (28 frames x 15), but a share of
        // real skins ship it TRIMMED to 418/419px. The last frame's bottom is
        // capped at 418 so rects must fit 418 (not 420) to stay in-bounds there.
        "volume.bmp":   (68, 418),
        // balance is NARROWER than volume: canonical frame is 47 wide, and a
        // large share of real skins ship balance.bmp at exactly 47px wide, so
        // rects must fit 47 (not 68). Its bottom is likewise capped at 418 to fit
        // the trimmed 418/419px sheets, so rects must fit 418 (not 420).
        "balance.bmp":  (47, 418),
        // text.bmp is 155 wide; height varies (18 / 73 / 74). Use the SMALLEST
        // observed height so any rect fitting here fits every real sheet.
        "text.bmp":     (155, 18),
        // pledit.bmp (playlist window frame). Measured across the ~200-skin
        // corpus: width is 280 in 188/191 skins (smallest non-degenerate 276);
        // height is 186 (modal, 127 skins) or 190 (60 skins), smallest 186. Use
        // the SMALLEST real sheet — 276 x 186 — so any rect fitting here fits
        // every real pledit.bmp. See testPleditStandardSizeIsMeasuredSmallest for
        // the NON-circular pin to those measured numbers.
        "pledit.bmp":   (276, 186)
    ]

    /// Every sheet across BOTH the main-window and playlist-window tables, so a
    /// newly added playlist sheet is covered by the same fit guard.
    private var allSheets: [String: [SpriteRect]] {
        SpriteCoordinates.mainWindow.merging(SpriteCoordinates.playlistWindow) { a, _ in a }
    }

    func testEverySpriteRectFitsItsStandardSheetDimensions() {
        for (sheet, rects) in allSheets {
            guard let dims = Self.standardDimensions[sheet] else {
                XCTFail("no standard dimensions declared for sheet \(sheet)")
                continue
            }
            for rect in rects {
                XCTAssertGreaterThanOrEqual(
                    rect.x, 0, "\(sheet)/\(rect.name): x must be >= 0")
                XCTAssertGreaterThanOrEqual(
                    rect.y, 0, "\(sheet)/\(rect.name): y must be >= 0")
                XCTAssertLessThanOrEqual(
                    rect.x + rect.width, dims.width,
                    "\(sheet)/\(rect.name): right edge \(rect.x + rect.width) "
                        + "exceeds sheet width \(dims.width)")
                XCTAssertLessThanOrEqual(
                    rect.y + rect.height, dims.height,
                    "\(sheet)/\(rect.name): bottom edge \(rect.y + rect.height) "
                        + "exceeds sheet height \(dims.height)")
            }
        }
    }

    /// Pins the balance slider frame width to its canonical 47px. The balance
    /// sheet is narrower than volume (68px); a regression back to 68 would
    /// silently read past the right edge of the many real skins that ship
    /// balance.bmp at 47px wide, making the control invisible there. Asserts
    /// directly against the coordinate table so it does not rely on the fit
    /// fixtures above.
    func testBalanceFrameWidthIsPinnedTo47() {
        guard let balance = SpriteCoordinates.mainWindow["balance.bmp"] else {
            XCTFail("balance.bmp missing from the coordinate table")
            return
        }
        XCTAssertEqual(balance.count, 28, "balance must have 28 stacked frames")
        for (index, rect) in balance.enumerated() {
            XCTAssertEqual(
                rect.width, 47,
                "\(rect.name): balance frame width must be 47 (canonical), not "
                    + "68 — a 68-wide frame overruns 47px-wide balance sheets")
            // Every frame is 15 tall except the LAST, whose bottom is capped at
            // 418 to fit the trimmed 418/419px sheets (see
            // testBalanceMaxBottomIsPinnedTo418). That final frame is therefore
            // 13 tall (418 - 27*15); all earlier frames remain 15.
            if index == balance.count - 1 {
                XCTAssertEqual(
                    rect.height, 13,
                    "\(rect.name): last balance frame is capped at 13 (bottom 418)")
            } else {
                XCTAssertEqual(
                    rect.height, 15, "\(rect.name): balance frame height must be 15")
            }
        }
    }

    /// Pins the volume slider's maximum bottom edge to 418px. Volume's nominal
    /// content height is 28 * 15 = 420, but a meaningful share of real skins ship
    /// volume.bmp trimmed to 418/419px; a 420-bottom last frame (level27) overruns
    /// those sheets, and `SpriteCutter` then drops it, leaving the 28-frame set
    /// incomplete and the slider blank at that level. Capping the last frame's
    /// bottom at 418 keeps every level in-bounds. Asserts directly against the
    /// coordinate table so it does not rely on the fit fixtures above.
    func testVolumeMaxBottomIsPinnedTo418() {
        guard let volume = SpriteCoordinates.mainWindow["volume.bmp"] else {
            XCTFail("volume.bmp missing from the coordinate table")
            return
        }
        XCTAssertEqual(volume.count, 28, "volume must have 28 stacked frames")
        let maxBottom = volume.map { $0.y + $0.height }.max()
        XCTAssertEqual(
            maxBottom, 418,
            "volume max bottom edge must be 418, not 420 — a 420 bottom overruns "
                + "the 418/419px-tall volume sheets and drops the whole sheet")
        for rect in volume {
            XCTAssertEqual(rect.width, 68, "\(rect.name): volume frame width must be 68")
        }
    }

    /// Pins the balance slider's maximum bottom edge to 418px, the same trim the
    /// volume sheet needs (balance shares the 28 * 15 = 420 nominal height and the
    /// same 418/419px real-sheet exposure). A 420 bottom overruns those sheets and
    /// `SpriteCutter` drops the whole balance control. Asserts directly against
    /// the coordinate table.
    func testBalanceMaxBottomIsPinnedTo418() {
        guard let balance = SpriteCoordinates.mainWindow["balance.bmp"] else {
            XCTFail("balance.bmp missing from the coordinate table")
            return
        }
        let maxBottom = balance.map { $0.y + $0.height }.max()
        XCTAssertEqual(
            maxBottom, 418,
            "balance max bottom edge must be 418, not 420 — a 420 bottom overruns "
                + "the 418/419px-tall balance sheets and drops the whole sheet")
    }

    /// Pins the canonical posbar geometry to 307x10. The seek track is 248 wide
    /// at x=0, and the two 29-wide thumb sub-bitmaps live at x=248 and x=278, so
    /// the rects occupy x 0..306 (right edge 307) and are all 10px tall. These
    /// coordinates are correct on the ~96.5% modal 307x10 sheet and MUST NOT be
    /// shrunk to chase the 248-wide / short-strip minorities: clamping the thumb
    /// x would corrupt the canonical majority. Asserts directly against the table.
    func testPosbarGeometryIsPinnedToCanonical307x10() {
        guard let posbar = SpriteCoordinates.mainWindow["posbar.bmp"] else {
            XCTFail("posbar.bmp missing from the coordinate table")
            return
        }
        let byName = Dictionary(uniqueKeysWithValues: posbar.map { ($0.name, $0) })

        let track = try? XCTUnwrap(byName["track"])
        XCTAssertEqual(track?.x, 0, "track x")
        XCTAssertEqual(track?.y, 0, "track y")
        XCTAssertEqual(track?.width, 248, "track width must be 248 (canonical seek track)")
        XCTAssertEqual(track?.height, 10, "track height must be 10 (canonical)")

        let thumb = try? XCTUnwrap(byName["thumb"])
        XCTAssertEqual(thumb?.x, 248, "thumb x must be 248 — the dynamic thumb lives here")
        XCTAssertEqual(thumb?.width, 29, "thumb width must be 29")
        XCTAssertEqual(thumb?.height, 10, "thumb height must be 10")

        let thumbPressed = try? XCTUnwrap(byName["thumbPressed"])
        XCTAssertEqual(thumbPressed?.x, 278, "thumbPressed x must be 278")
        XCTAssertEqual(thumbPressed?.width, 29, "thumbPressed width must be 29")
        XCTAssertEqual(thumbPressed?.height, 10, "thumbPressed height must be 10")

        let maxRight = posbar.map { $0.x + $0.width }.max()
        XCTAssertEqual(
            maxRight, 307,
            "posbar max right edge must be 307 (canonical sheet width); do not "
                + "shrink the thumb x to chase 248-wide minority sheets")
    }

    /// Every sheet declared in either coordinate table must have a standard-size
    /// entry here, so a newly added sheet cannot silently skip the fit check.
    func testEveryTableSheetHasStandardDimensions() {
        for sheet in allSheets.keys {
            XCTAssertNotNil(
                Self.standardDimensions[sheet],
                "sheet \(sheet) is in the coordinate table but has no standard "
                    + "dimensions in the fit test")
        }
    }

    // MARK: - pledit.bmp (playlist window frame) — balance-bug guard

    /// NON-CIRCULAR pin: the standard pledit.bmp size used by the fit test must
    /// equal the values actually MEASURED from the real corpus, not whatever the
    /// coordinate table happens to declare. Measured June 2026 over ~200 skins
    /// (191 carried pledit.bmp): width was 280 in 188 skins, smallest
    /// non-degenerate 276 (S.E.wsz); height was 186 in 127 skins and 190 in 60,
    /// smallest 186. The fit floor is the SMALLEST real sheet, 276 x 186. If a
    /// future edit widens this floor past the real minimum, this test fails —
    /// which is exactly the balance-bug class (declaring a sheet bigger than real
    /// skins ship, so rects silently overrun and the piece vanishes).
    func testPleditStandardSizeIsMeasuredSmallest() {
        let dims = Self.standardDimensions["pledit.bmp"]
        XCTAssertEqual(
            dims?.width, 276,
            "pledit.bmp fit width must be the smallest measured real width (276), "
                + "not the modal 280 — a rect fitting 280 could overrun the 276px skins")
        XCTAssertEqual(
            dims?.height, 186,
            "pledit.bmp fit height must be the smallest measured real height (186)")
    }

    /// The playlist frame must declare the core pieces needed to composite the
    /// resizable window — title corners + fills (active and inactive), side edges,
    /// the bottom frame, and the scrollbar handle — and every one must fit inside
    /// the smallest real sheet (276 x 186). Asserts directly against the table so
    /// it does not lean on the generic fit loop.
    func testPlaylistFrameHasCorePiecesThatFitTheSmallestRealSheet() {
        guard let frame = SpriteCoordinates.playlistWindow["pledit.bmp"] else {
            XCTFail("pledit.bmp missing from the playlist coordinate table")
            return
        }
        let names = Set(frame.map(\.name))
        let required: Set<String> = [
            "titleBarLeftCorner", "titleBarTitleActive", "titleBarFillActive", "titleBarRightCorner",
            "titleBarLeftCornerInactive", "titleBarTitleInactive", "titleBarFillInactive",
            "titleBarRightCornerInactive",
            "leftEdge", "rightEdge",
            "bottomLeftCorner", "bottomFill", "bottomRightCorner",
            "scrollHandle"
        ]
        XCTAssertTrue(
            required.isSubset(of: names),
            "playlist frame is missing core pieces: \(required.subtracting(names))")

        // Hard fit floor: the smallest real pledit.bmp is 276 x 186. No rect may
        // overrun it (the balance-bug failure mode: SpriteCutter drops an
        // out-of-bounds rect, so the piece silently disappears on real skins).
        for rect in frame {
            XCTAssertGreaterThanOrEqual(rect.x, 0, "\(rect.name): x >= 0")
            XCTAssertGreaterThanOrEqual(rect.y, 0, "\(rect.name): y >= 0")
            XCTAssertGreaterThan(rect.width, 0, "\(rect.name): width > 0")
            XCTAssertGreaterThan(rect.height, 0, "\(rect.name): height > 0")
            XCTAssertLessThanOrEqual(
                rect.x + rect.width, 276,
                "\(rect.name): right edge \(rect.x + rect.width) overruns smallest "
                    + "real pledit width 276")
            XCTAssertLessThanOrEqual(
                rect.y + rect.height, 186,
                "\(rect.name): bottom edge \(rect.y + rect.height) overruns smallest "
                    + "real pledit height 186")
        }
    }

    /// Pins the title-bar split: a SEPARATE centered title piece (drawn once) and
    /// a NARROW tiling texture fill that is NOT the title text. Regressing the fill
    /// back to the 100px title region reintroduces the "repeated title" bug (the
    /// composer tiled the title across the whole width). The title piece is the
    /// ~100px label at x = 26; the fill is the ~25px tileable band at x = 127;
    /// both active (y = 0) and inactive (y = 21) variants. All inside 276 x 186.
    func testTitleAndFillAreSeparatePinnedRegions() {
        guard let frame = SpriteCoordinates.playlistWindow["pledit.bmp"] else {
            XCTFail("pledit.bmp missing from the playlist coordinate table")
            return
        }
        let byName = Dictionary(uniqueKeysWithValues: frame.map { ($0.name, $0) })

        func check(_ name: String, x: Int, y: Int, w: Int, h: Int) {
            guard let r = byName[name] else { XCTFail("\(name) missing"); return }
            XCTAssertEqual(r.x, x, "\(name) x"); XCTAssertEqual(r.y, y, "\(name) y")
            XCTAssertEqual(r.width, w, "\(name) width"); XCTAssertEqual(r.height, h, "\(name) height")
        }
        check("titleBarTitleActive",   x: 26,  y: 0,  w: 100, h: 20)
        check("titleBarTitleInactive", x: 26,  y: 21, w: 100, h: 20)
        // The fill must be the NARROW texture strip, distinct from the title region.
        check("titleBarFillActive",    x: 127, y: 0,  w: 25,  h: 20)
        check("titleBarFillInactive",  x: 127, y: 21, w: 25,  h: 20)

        // The fill rect must NOT coincide with the title rect (that overlap WAS the
        // bug — the title region was used as the tiled fill).
        let title = byName["titleBarTitleActive"]
        let fill = byName["titleBarFillActive"]
        XCTAssertNotEqual(title?.x, fill?.x, "fill must not start where the title does")
        XCTAssertLessThan(
            fill?.width ?? .max, title?.width ?? 0,
            "fill (narrow texture) must be narrower than the title piece")
    }
}
