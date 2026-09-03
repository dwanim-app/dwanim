import Foundation
import XCTest
@testable import PlayerCore

/// Tests for `PlayerCore.move(fromOffsets:toOffset:)` — the drag-to-reorder
/// seam the default (Cadence) playlist's `onMove` calls. It mirrors Swift's
/// `Array.move(fromOffsets:toOffset:)` convention exactly (and therefore
/// SwiftUI's `onMove`): the rows at `fromOffsets` are lifted out, keep their
/// relative order, and are inserted before the row that was at `toOffset` in
/// the ORIGINAL list (`toOffset == count` means "to the very end").
///
/// The rule under test is the shared EDIT RULE: `currentIndex` FOLLOWS THE
/// PLAYING TRACK. Moving the playing row moves the now-playing marker with it;
/// moving other rows across it remaps the index so it still names the same
/// track; the engine is never touched (no reload, no stop). Next / previous
/// after a move walk the NEW order.
@MainActor
final class PlayerCoreMoveTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    /// Load `names` and, when `playing` is given, start playing that row.
    private func loadedCore(
        engine: FakePlaybackEngine = FakePlaybackEngine(),
        names: [String] = ["a", "b", "c", "d"],
        playing: Int? = nil,
        shuffle: ((_ count: Int, _ current: Int?) -> Int)? = nil
    ) -> PlayerCore {
        let core = PlayerCore(
            engine: engine,
            shuffleStrategy: shuffle ?? PlayerCore.defaultShuffleStrategy
        )
        core.load(names.map { track($0) })
        if let playing {
            core.select(playing)
        }
        return core
    }

    private func names(of core: PlayerCore) -> [String] {
        core.playlist.map { $0.url.deletingPathExtension().lastPathComponent }
    }

    private func currentName(of core: PlayerCore) -> String? {
        core.currentTrack?.url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Single row up / down

    func testMoveOneRowUp() {
        let core = loadedCore(playing: 3) // playing "d"

        core.move(fromOffsets: [2], toOffset: 0)

        XCTAssertEqual(names(of: core), ["c", "a", "b", "d"])
        XCTAssertEqual(core.currentIndex, 3) // "d" did not move
        XCTAssertEqual(currentName(of: core), "d")
    }

    func testMoveOneRowDown() {
        let core = loadedCore(playing: 3) // playing "d"

        core.move(fromOffsets: [0], toOffset: 3) // before the row that WAS at 3 ("d")

        XCTAssertEqual(names(of: core), ["b", "c", "a", "d"])
        XCTAssertEqual(core.currentIndex, 3)
        XCTAssertEqual(currentName(of: core), "d")
    }

    // MARK: - The playing row itself: the now-playing marker follows it

    func testMovingThePlayingRowKeepsItPlayingAndFollowsIt() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 2) // playing "c"

        core.move(fromOffsets: [2], toOffset: 0)

        XCTAssertEqual(names(of: core), ["c", "a", "b", "d"])
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(currentName(of: core), "c")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 0, "the engine must not be stopped")
        XCTAssertEqual(engine.loadedURLs.count, 1, "no reload — the audio never skips")
        XCTAssertEqual(engine.playCount, 1)
    }

    func testMovingThePlayingRowToTheEndFollowsIt() {
        let core = loadedCore(playing: 0) // playing "a"

        core.move(fromOffsets: [0], toOffset: 4)

        XCTAssertEqual(names(of: core), ["b", "c", "d", "a"])
        XCTAssertEqual(core.currentIndex, 3)
        XCTAssertEqual(currentName(of: core), "a")
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - Other rows across the playing one: the index remaps, same track

    func testMovingARowFromBelowToAboveThePlayingRowRemapsCurrent() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1) // playing "b"

        core.move(fromOffsets: [3], toOffset: 0)

        XCTAssertEqual(names(of: core), ["d", "a", "b", "c"])
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertEqual(currentName(of: core), "b")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }

    func testMovingARowFromAboveToBelowThePlayingRowRemapsCurrent() {
        let core = loadedCore(playing: 2) // playing "c"

        core.move(fromOffsets: [0], toOffset: 4)

        XCTAssertEqual(names(of: core), ["b", "c", "d", "a"])
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(currentName(of: core), "c")
    }

    // MARK: - Multi-selection (contiguous and non-contiguous)

    func testMoveContiguousSelectionDown() {
        let core = loadedCore(names: ["a", "b", "c", "d", "e"], playing: 4) // playing "e"

        core.move(fromOffsets: [1, 2], toOffset: 5)

        XCTAssertEqual(names(of: core), ["a", "d", "e", "b", "c"])
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertEqual(currentName(of: core), "e")
    }

    func testMoveNonContiguousSelectionKeepsRelativeOrder() {
        let core = loadedCore(names: ["a", "b", "c", "d", "e"], playing: 4) // playing "e"

        core.move(fromOffsets: [0, 2], toOffset: 4) // before the row that WAS at 4 ("e")

        XCTAssertEqual(names(of: core), ["b", "d", "a", "c", "e"])
        XCTAssertEqual(core.currentIndex, 4)
        XCTAssertEqual(currentName(of: core), "e")
    }

    func testMoveSelectionContainingThePlayingRowFollowsIt() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, names: ["a", "b", "c", "d", "e"], playing: 2) // "c"

        core.move(fromOffsets: [0, 2], toOffset: 5)

        XCTAssertEqual(names(of: core), ["b", "d", "e", "a", "c"])
        XCTAssertEqual(core.currentIndex, 4)
        XCTAssertEqual(currentName(of: core), "c")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }

    func testMoveNonContiguousSelectionUp() {
        let core = loadedCore(names: ["a", "b", "c", "d", "e"], playing: 0) // "a"

        core.move(fromOffsets: [2, 4], toOffset: 1)

        XCTAssertEqual(names(of: core), ["a", "c", "e", "b", "d"])
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(currentName(of: core), "a")
    }

    // MARK: - No-op moves leave order AND current index untouched

    func testMoveToItsOwnPositionIsNoOp() {
        let core = loadedCore(playing: 1)

        core.move(fromOffsets: [1], toOffset: 1)

        XCTAssertEqual(names(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testMoveToTheSlotJustAfterItselfIsNoOp() {
        let core = loadedCore(playing: 1)

        core.move(fromOffsets: [1], toOffset: 2) // "before the row that was at 2" == where it is

        XCTAssertEqual(names(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testMoveContiguousBlockWithinItselfIsNoOp() {
        let core = loadedCore(playing: 2)

        core.move(fromOffsets: [1, 2], toOffset: 2) // destination inside the block
        core.move(fromOffsets: [1, 2], toOffset: 3) // right after the block

        XCTAssertEqual(names(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 2)
    }

    // MARK: - Empty / out-of-range are safe no-ops

    func testMoveOnEmptyPlaylistIsSafe() {
        let core = PlayerCore(engine: FakePlaybackEngine())

        core.move(fromOffsets: [0], toOffset: 0)
        core.move(fromOffsets: [0], toOffset: 1)

        XCTAssertTrue(core.playlist.isEmpty)
        XCTAssertNil(core.currentIndex)
    }

    func testMoveOnSingleTrackPlaylistIsNoOp() {
        let core = loadedCore(names: ["only"], playing: 0)

        core.move(fromOffsets: [0], toOffset: 1)
        core.move(fromOffsets: [0], toOffset: 0)

        XCTAssertEqual(names(of: core), ["only"])
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertTrue(core.isPlaying)
    }

    func testMoveWithOutOfRangeOffsetsIsIgnored() {
        let core = loadedCore(playing: 1)

        core.move(fromOffsets: [9, 42], toOffset: 0)
        core.move(fromOffsets: [], toOffset: 0)

        XCTAssertEqual(names(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testMoveWithOutOfRangeDestinationIsIgnored() {
        let core = loadedCore(playing: 1)

        core.move(fromOffsets: [0], toOffset: 5)  // past "the end" slot (count == 4)
        core.move(fromOffsets: [0], toOffset: -1)

        XCTAssertEqual(names(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1)
    }

    /// Out-of-range members of a partly valid set are dropped, and the valid
    /// remainder still moves (mirrors `remove(at:)`'s tolerance).
    func testMoveWithPartlyOutOfRangeOffsetsMovesTheValidRows() {
        let core = loadedCore(playing: 3)

        core.move(fromOffsets: [0, 9], toOffset: 4)

        XCTAssertEqual(names(of: core), ["b", "c", "d", "a"])
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertEqual(currentName(of: core), "d")
    }

    // MARK: - Next / previous after a move follow the NEW order

    func testNextAfterMoveFollowsTheNewOrder() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 0) // playing "a"

        core.move(fromOffsets: [3], toOffset: 1) // "d" now right after "a"
        XCTAssertEqual(names(of: core), ["a", "d", "b", "c"])

        core.next()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "d.mp3")
        XCTAssertTrue(core.isPlaying)
    }

    func testPreviousAfterMoveFollowsTheNewOrder() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 2) // playing "c"

        core.move(fromOffsets: [0], toOffset: 4) // "a" to the end -> [b, c, d, a]
        XCTAssertEqual(core.currentIndex, 1)

        core.previous()

        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "b.mp3")
    }

    func testNextAfterMovingThePlayingRowToTheEndStopsWithRepeatOff() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 0) // playing "a"
        core.repeatMode = .off

        core.move(fromOffsets: [0], toOffset: 4) // "a" is now last
        core.next()

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(core.currentIndex, 3, "selection clamps to the (new) last row")
    }

    func testPlaybackFinishedAfterMoveAdvancesInTheNewOrder() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1) // playing "b"

        core.move(fromOffsets: [3], toOffset: 2) // "d" right after "b" -> [a, b, d, c]
        engine.fireFinished()

        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "d.mp3")
    }

    // MARK: - Shuffle: the pick is resolved against the NEW order (no stale state)

    /// Shuffle keeps no precomputed order that a reorder could desync — `next`
    /// asks the strategy for an index against the live list. A strategy that
    /// picks index 1 after a move therefore lands on whatever NOW sits at 1.
    func testShuffleNextAfterMovePicksFromTheNewOrder() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 3, shuffle: { _, _ in 1 }) // playing "d"
        core.isShuffle = true

        core.move(fromOffsets: [3], toOffset: 0) // [d, a, b, c]; "d" followed to 0
        XCTAssertEqual(core.currentIndex, 0)

        core.next()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "a.mp3")
    }

    // MARK: - Paused: resume stays on the same (followed) track without reload

    func testMoveWhilePausedResumesTheSameTrackWithoutReload() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1) // "b"
        core.pause()

        core.move(fromOffsets: [1], toOffset: 4) // "b" to the end -> [a, c, d, b]
        XCTAssertEqual(core.currentIndex, 3)

        core.play()

        XCTAssertEqual(engine.loadedURLs.count, 1, "resume, not reload")
        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "b.mp3")
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - Idle (selected, not playing): the selection follows too

    func testMoveFollowsAnIdleSelectionWithoutPlaying() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine) // load selects row 0 ("a"), nothing plays

        core.move(fromOffsets: [0], toOffset: 3)

        XCTAssertEqual(names(of: core), ["b", "c", "a", "d"])
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertTrue(engine.loadedURLs.isEmpty)
    }
}
