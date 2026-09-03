import Foundation
import XCTest

@testable import DwanimItUI

// MARK: - PlaylistSelectionTests

/// Tests for `PlaylistSelection`, the pure seam that carries the Cadence
/// playlist's INDEX-based `List` selection across a structural change of the
/// queue (keyed on the track URLs, exactly what the view's `onChange` observes).
///
/// The contract: on a pure REORDER (same tracks, new positions — a drag-to-
/// reorder, sort, reverse, or randomize) the selection FOLLOWS THE TRACKS to
/// their new rows; on any other structural change (add / remove / replace) it
/// clears, which is the pre-existing behaviour the view relied on before
/// drag-reorder existed (an index-based selection is stale after rows shift).
///
/// "Reorder" means the same MULTISET of URLs: a same-count change whose
/// membership differs (a replaced track, or a duplicate row swapped for another
/// file) is not a reorder even when every selected row happens to survive it.
final class PlaylistSelectionTests: XCTestCase {

    private func urls(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/music/\($0).mp3") }
    }

    // MARK: - Reorder: the selection follows the tracks

    func testSingleSelectionFollowsItsTrackAfterAReorder() {
        let old = urls("a", "b", "c", "d")
        let new = urls("c", "a", "b", "d") // "c" dragged to the top

        let followed = PlaylistSelection.following([2], from: old, to: new)

        XCTAssertEqual(followed, [0])
    }

    func testMultiSelectionFollowsEachTrackAfterAReorder() {
        let old = urls("a", "b", "c", "d", "e")
        let new = urls("b", "d", "a", "c", "e") // {a, c} dragged before "e"

        let followed = PlaylistSelection.following([0, 2], from: old, to: new)

        XCTAssertEqual(followed, [2, 3])
    }

    func testUnmovedSelectionIsRemappedWhenOtherRowsCrossIt() {
        let old = urls("a", "b", "c", "d")
        let new = urls("d", "a", "b", "c") // "d" dragged to the top, across a selected "b"

        let followed = PlaylistSelection.following([1], from: old, to: new)

        XCTAssertEqual(followed, [2])
    }

    func testIdenticalOrderKeepsTheSelection() {
        let list = urls("a", "b", "c")

        XCTAssertEqual(PlaylistSelection.following([0, 2], from: list, to: list), [0, 2])
    }

    func testDuplicateURLsFollowByOccurrence() {
        // Two rows for the same file (a loaded .m3u can repeat an entry): each
        // selected occurrence maps to the matching occurrence in the new order,
        // so two selected rows never collapse into one.
        let old = urls("x", "x", "y")
        let new = urls("y", "x", "x")

        let followed = PlaylistSelection.following([0, 1], from: old, to: new)

        XCTAssertEqual(followed, [1, 2])
    }

    // MARK: - Add / remove / replace: the index-based selection clears (pre-existing rule)

    func testAppendClearsTheSelection() {
        let old = urls("a", "b")
        let new = urls("a", "b", "c")

        XCTAssertEqual(PlaylistSelection.following([1], from: old, to: new), [])
    }

    func testRemoveClearsTheSelection() {
        let old = urls("a", "b", "c")
        let new = urls("a", "c")

        XCTAssertEqual(PlaylistSelection.following([2], from: old, to: new), [])
    }

    func testReplacementOfATrackClearsTheSelection() {
        // Same count, different membership: not a reorder.
        let old = urls("a", "b", "c")
        let new = urls("a", "z", "c")

        XCTAssertEqual(PlaylistSelection.following([1], from: old, to: new), [])
    }

    func testReplacementClearsASelectedTrackThatSurvivedTheChange() {
        // Same count, different membership, and the SELECTED row ("a") is still
        // present at the same index in the new list. This pins the reorder
        // guard itself: a plain count check would call this a reorder and keep
        // row 0 highlighted, but the queue's membership changed, so the
        // documented clear-on-change rule must win and the selection clears.
        let old = urls("a", "b", "c")
        let new = urls("a", "z", "c")

        XCTAssertEqual(PlaylistSelection.following([0], from: old, to: new), [])
    }

    func testSameURLSetWithADifferentMultisetIsNotAReorder() {
        // Same count and the same SET of URLs {x, y}, but a different multiset:
        // {x, x, y} became {x, y, y}. That is a replace (an "x" row became a
        // "y" row), not a reorder, so the selection clears. A set-based
        // membership check would wrongly treat it as a reorder and follow the
        // selected rows to [0, 1].
        let old = urls("x", "x", "y")
        let new = urls("x", "y", "y")

        XCTAssertEqual(PlaylistSelection.following([0, 2], from: old, to: new), [])
    }

    // MARK: - Degenerate input

    func testEmptySelectionStaysEmpty() {
        let old = urls("a", "b")
        let new = urls("b", "a")

        XCTAssertEqual(PlaylistSelection.following([], from: old, to: new), [])
    }

    func testOutOfRangeSelectionIndicesAreDropped() {
        let old = urls("a", "b")
        let new = urls("b", "a")

        XCTAssertEqual(PlaylistSelection.following([1, 7, -1], from: old, to: new), [0])
    }

    func testEmptyListsYieldEmptySelection() {
        XCTAssertEqual(PlaylistSelection.following([0], from: [], to: []), [])
    }
}
