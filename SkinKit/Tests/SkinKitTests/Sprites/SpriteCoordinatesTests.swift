import Foundation
import XCTest
@testable import SkinKit

/// Tests for the static coordinate table describing where the main player
/// window sprites live inside each sheet of the classic `.wsz` skin format.
/// These assert structural invariants (presence, consistency, the committed
/// `cbuttons.bmp` layout) rather than re-validating exact pixel rectangles,
/// which is done separately against real sheets.
final class SpriteCoordinatesTests: XCTestCase {

    private var table: [String: [SpriteRect]] { SpriteCoordinates.mainWindow }

    // MARK: - Criterion 5: the expected sheets are present

    func testMainWindowContainsExpectedSheets() {
        let keys = Set(table.keys)
        for sheet in ["cbuttons.bmp", "titlebar.bmp", "shufrep.bmp",
                      "posbar.bmp", "volume.bmp", "balance.bmp",
                      "monoster.bmp", "playpaus.bmp", "numbers.bmp", "text.bmp"] {
            XCTAssertTrue(keys.contains(sheet), "expected sheet \(sheet) to be present")
        }
    }

    func testSheetKeysAreLowercasedFilenames() {
        for key in table.keys {
            XCTAssertEqual(key, key.lowercased(), "sheet key \(key) should be lowercased")
            XCTAssertTrue(key.hasSuffix(".bmp"), "sheet key \(key) should be a .bmp filename")
        }
    }

    // MARK: - Criterion 6: internal consistency

    func testEverySpriteRectHasSaneGeometry() {
        for (sheet, rects) in table {
            for rect in rects {
                XCTAssertGreaterThanOrEqual(rect.x, 0, "\(sheet)/\(rect.name) x must be >= 0")
                XCTAssertGreaterThanOrEqual(rect.y, 0, "\(sheet)/\(rect.name) y must be >= 0")
                XCTAssertGreaterThan(rect.width, 0, "\(sheet)/\(rect.name) width must be > 0")
                XCTAssertGreaterThan(rect.height, 0, "\(sheet)/\(rect.name) height must be > 0")
            }
        }
    }

    func testSpriteNamesAreUniqueWithinEachSheet() {
        for (sheet, rects) in table {
            let names = rects.map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "duplicate sprite name in \(sheet)")
        }
    }

    func testNoSheetIsEmpty() {
        for (sheet, rects) in table {
            XCTAssertFalse(rects.isEmpty, "sheet \(sheet) should declare at least one sprite")
        }
    }

    // MARK: - Criterion 7: cbuttons.bmp transport buttons + pressed states

    func testTransportButtonsAreModelledWithPressedStates() {
        let cbuttons = try! XCTUnwrap(table["cbuttons.bmp"])
        let names = Set(cbuttons.map(\.name))

        let expected: Set<String> = [
            "previous", "previousPressed",
            "play", "playPressed",
            "pause", "pausePressed",
            "stop", "stopPressed",
            "next", "nextPressed"
        ]
        XCTAssertEqual(names, expected)
        XCTAssertEqual(cbuttons.count, 10)

        // The five main transport buttons share one footprint; the eject button
        // is a different size and is intentionally not part of this set.
        for rect in cbuttons {
            XCTAssertEqual(rect.width, 23, "\(rect.name) width")
            XCTAssertEqual(rect.height, 18, "\(rect.name) height")
        }
    }

    // MARK: - numbers / text fonts have the expected glyph counts

    func testNumbersSheetHasTenDigits() {
        let numbers = try! XCTUnwrap(table["numbers.bmp"])
        XCTAssertEqual(numbers.count, 10)
        let names = Set(numbers.map(\.name))
        XCTAssertEqual(names, Set((0...9).map { "digit\($0)" }))
    }

    // MARK: - playlist window table

    func testPlaylistWindowContainsPledit() {
        XCTAssertTrue(
            SpriteCoordinates.playlistWindow.keys.contains("pledit.bmp"),
            "playlistWindow should contain pledit.bmp")
    }

    func testPlaylistWindowKeysAreLowercasedBmpFilenames() {
        for key in SpriteCoordinates.playlistWindow.keys {
            XCTAssertEqual(key, key.lowercased(), "sheet key \(key) should be lowercased")
            XCTAssertTrue(key.hasSuffix(".bmp"), "sheet key \(key) should be a .bmp filename")
        }
    }

    func testPlaylistAndMainWindowTablesKeyDisjointSheets() {
        let main = Set(SpriteCoordinates.mainWindow.keys)
        let pl = Set(SpriteCoordinates.playlistWindow.keys)
        XCTAssertTrue(
            main.isDisjoint(with: pl),
            "main-window and playlist-window tables must not share a sheet "
                + "filename (SkinLoader merges them in one pass): \(main.intersection(pl))")
    }

    /// All THREE sprite tables (main, playlist, equalizer) must key pairwise
    /// disjoint sheets — SkinLoader merges them in a single pass, so a shared
    /// filename would be double-processed / clobbered.
    func testAllThreeWindowTablesKeyPairwiseDisjointSheets() {
        let main = Set(SpriteCoordinates.mainWindow.keys)
        let pl = Set(SpriteCoordinates.playlistWindow.keys)
        let eq = Set(SpriteCoordinates.equalizerWindow.keys)
        XCTAssertTrue(
            main.isDisjoint(with: eq),
            "main-window and equalizer-window tables share a sheet: "
                + "\(main.intersection(eq))")
        XCTAssertTrue(
            pl.isDisjoint(with: eq),
            "playlist-window and equalizer-window tables share a sheet: "
                + "\(pl.intersection(eq))")
        XCTAssertTrue(
            main.isDisjoint(with: pl),
            "main-window and playlist-window tables share a sheet: "
                + "\(main.intersection(pl))")
    }

    // MARK: - equalizer window table

    func testEqualizerWindowContainsEqmain() {
        XCTAssertTrue(
            SpriteCoordinates.equalizerWindow.keys.contains("eqmain.bmp"),
            "equalizerWindow should contain eqmain.bmp")
    }

    func testEqualizerWindowKeysAreLowercasedBmpFilenames() {
        for key in SpriteCoordinates.equalizerWindow.keys {
            XCTAssertEqual(key, key.lowercased(), "sheet key \(key) should be lowercased")
            XCTAssertTrue(key.hasSuffix(".bmp"), "sheet key \(key) should be a .bmp filename")
        }
    }

    /// The EQ windowshade sheet (`eq_ex.bmp`) is DEFERRED and must NOT be keyed in
    /// the equalizer table yet (documented deferral).
    func testEqualizerWindowDefersEqExWindowshade() {
        XCTAssertFalse(
            SpriteCoordinates.equalizerWindow.keys.contains("eq_ex.bmp"),
            "eq_ex.bmp (windowshade variant) is deferred and must not be keyed yet")
    }

    func testEqualizerFaceSpriteGeometryIsSane() {
        for (sheet, rects) in SpriteCoordinates.equalizerWindow {
            XCTAssertFalse(rects.isEmpty, "sheet \(sheet) should declare at least one sprite")
            let names = rects.map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "duplicate sprite name in \(sheet)")
            for rect in rects {
                XCTAssertGreaterThanOrEqual(rect.x, 0, "\(sheet)/\(rect.name) x >= 0")
                XCTAssertGreaterThanOrEqual(rect.y, 0, "\(sheet)/\(rect.name) y >= 0")
                XCTAssertGreaterThan(rect.width, 0, "\(sheet)/\(rect.name) width > 0")
                XCTAssertGreaterThan(rect.height, 0, "\(sheet)/\(rect.name) height > 0")
            }
        }
    }

    /// The EQ face must carry a single full-window 275x116 background, the shared
    /// slider thumb pair, and the ON/AUTO toggle pairs.
    func testEqualizerFaceModelsBackgroundThumbAndToggles() {
        let eq = try! XCTUnwrap(SpriteCoordinates.equalizerWindow["eqmain.bmp"])
        let byName = Dictionary(uniqueKeysWithValues: eq.map { ($0.name, $0) })

        let bg = try! XCTUnwrap(byName["background"])
        XCTAssertEqual(bg.x, 0, "background x"); XCTAssertEqual(bg.y, 0, "background y")
        XCTAssertEqual(bg.width, 275, "EQ background width")
        XCTAssertEqual(bg.height, 116, "EQ background height (the 275x116 EQ face)")

        // The thumb (shared by preamp + 10 bands) has a normal and a pressed state
        // of identical size.
        let thumb = try! XCTUnwrap(byName["sliderThumb"])
        let thumbPressed = try! XCTUnwrap(byName["sliderThumbPressed"])
        XCTAssertEqual(thumb.width, thumbPressed.width, "thumb states share width")
        XCTAssertEqual(thumb.height, thumbPressed.height, "thumb states share height")

        // ON and AUTO each have off + on states.
        for name in ["onButtonOff", "onButtonOn", "autoButtonOff", "autoButtonOn"] {
            XCTAssertNotNil(byName[name], "EQ face missing toggle sprite \(name)")
        }
    }

    func testPlaylistFrameSpriteGeometryIsSane() {
        for (sheet, rects) in SpriteCoordinates.playlistWindow {
            XCTAssertFalse(rects.isEmpty, "sheet \(sheet) should declare at least one sprite")
            let names = rects.map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "duplicate sprite name in \(sheet)")
            for rect in rects {
                XCTAssertGreaterThanOrEqual(rect.x, 0, "\(sheet)/\(rect.name) x >= 0")
                XCTAssertGreaterThanOrEqual(rect.y, 0, "\(sheet)/\(rect.name) y >= 0")
                XCTAssertGreaterThan(rect.width, 0, "\(sheet)/\(rect.name) width > 0")
                XCTAssertGreaterThan(rect.height, 0, "\(sheet)/\(rect.name) height > 0")
            }
        }
    }

    func testMainBackgroundIsFullPlayerSize() {
        // main.bmp is the whole 275x116 window background; if present it must be
        // a single full-size rect.
        if let main = table["main.bmp"] {
            XCTAssertEqual(main.count, 1)
            XCTAssertEqual(main.first?.width, 275)
            XCTAssertEqual(main.first?.height, 116)
        }
    }
}
