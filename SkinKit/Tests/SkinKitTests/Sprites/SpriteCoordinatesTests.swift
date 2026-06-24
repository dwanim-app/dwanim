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
