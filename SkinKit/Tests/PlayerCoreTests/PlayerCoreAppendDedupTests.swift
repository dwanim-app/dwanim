import Foundation
import XCTest
@testable import PlayerCore

/// Tests for the DE-DUPLICATION contract on `PlayerCore.append` — the single
/// central append seam every ADD path routes through (drag-drop, Add Files…,
/// Add Folder…, the classic playlist window's ADD). Adding a track already in
/// the queue is a no-op FOR THAT TRACK: only the genuinely-new URLs are appended,
/// in order, and the existing order is preserved. If nothing is new the queue is
/// unchanged (and, upstream, no auto-play fires).
///
/// De-dup is by CANONICAL file URL (`standardizedFileURL`), so the same file
/// added by different path spellings is still one entry, while two different
/// files that merely share a display name are NOT duplicates.
@MainActor
final class PlayerCoreAppendDedupTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"), title: name)
    }

    private func makeCore() -> PlayerCore {
        PlayerCore(engine: FakePlaybackEngine())
    }

    /// A queue preloaded with A, B via `append` (so nothing is playing and the
    /// selection sits on row 0 — the state a user is in when they drag more in).
    private func coreWithAB() -> PlayerCore {
        let core = makeCore()
        core.append([track("A"), track("B")])
        return core
    }

    private func titles(of core: PlayerCore) -> [String] {
        core.playlist.map { $0.url.deletingPathExtension().lastPathComponent }
    }

    // MARK: - The six owner scenarios (queue already has A, B)

    /// 1. add {A, B} → no change (A, B).
    func testAddAllExistingIsNoChange() {
        let core = coreWithAB()
        core.append([track("A"), track("B")])
        XCTAssertEqual(titles(of: core), ["A", "B"])
    }

    /// 2. add {A} → no change (A, B).
    func testAddExistingFirstIsNoChange() {
        let core = coreWithAB()
        core.append([track("A")])
        XCTAssertEqual(titles(of: core), ["A", "B"])
    }

    /// 3. add {B} → no change (A, B).
    func testAddExistingSecondIsNoChange() {
        let core = coreWithAB()
        core.append([track("B")])
        XCTAssertEqual(titles(of: core), ["A", "B"])
    }

    /// 4. add {A, B, C} → A, B, C (only C is new).
    func testAddMixedWithOneNewAppendsOnlyTheNew() {
        let core = coreWithAB()
        core.append([track("A"), track("B"), track("C")])
        XCTAssertEqual(titles(of: core), ["A", "B", "C"])
    }

    /// 5. add {B, C} → A, B, C (only C is new).
    func testAddOneExistingOneNewAppendsOnlyTheNew() {
        let core = coreWithAB()
        core.append([track("B"), track("C")])
        XCTAssertEqual(titles(of: core), ["A", "B", "C"])
    }

    /// 6. add {C, D} → A, B, C, D (both new, appended in order).
    func testAddAllNewAppendsInOrder() {
        let core = coreWithAB()
        core.append([track("C"), track("D")])
        XCTAssertEqual(titles(of: core), ["A", "B", "C", "D"])
    }

    // MARK: - Ancillary de-dup guarantees

    /// Repeats WITHIN a single add batch collapse to one entry (first occurrence
    /// kept, order preserved).
    func testIntraBatchRepeatsCollapse() {
        let core = coreWithAB()
        core.append([track("C"), track("C"), track("D"), track("C")])
        XCTAssertEqual(titles(of: core), ["A", "B", "C", "D"])
    }

    /// The same FILE spelled with a non-standard path (`/music/./A.mp3`) is
    /// recognised as a duplicate of `/music/A.mp3` (canonical-URL de-dup).
    func testNonCanonicalSpellingOfExistingFileIsDuplicate() {
        let core = coreWithAB()
        core.append([Track(url: URL(fileURLWithPath: "/music/./A.mp3"))])
        XCTAssertEqual(titles(of: core), ["A", "B"])
    }

    /// Two DIFFERENT files that merely share a display name are NOT duplicates.
    func testDifferentFilesSharingANameAreNotDuplicates() {
        let core = coreWithAB()
        core.append([Track(url: URL(fileURLWithPath: "/other/A.mp3"))])
        XCTAssertEqual(core.playlist.count, 3)
        XCTAssertEqual(core.playlist.map(\.url.path),
                       ["/music/A.mp3", "/music/B.mp3", "/other/A.mp3"])
    }

    /// An all-duplicate add leaves the selection untouched (so upstream's
    /// "auto-play only if the queue was empty" never re-fires on a no-op add).
    func testAllDuplicateAddLeavesSelectionUntouched() {
        let core = coreWithAB()           // currentIndex == 0 after the first append
        let before = core.currentIndex
        core.append([track("A"), track("B")])
        XCTAssertEqual(core.currentIndex, before)
    }
}
