import Foundation
import XCTest
@testable import PlayerCore

/// Tests for `PlayerCore`'s playlist EDIT commands (append / remove / crop /
/// removeAll) and REORDER commands (sortByTitle / sortByFilename / reverse /
/// randomize), driven with a `FakePlaybackEngine` so every rule is asserted in
/// memory.
///
/// The shared EDIT RULE under test: `currentIndex` FOLLOWS THE PLAYING TRACK —
/// removals shift it by the rows removed before it, reorders recompute it to
/// the same track's new position, and only removing the current row itself
/// moves it (and stops playback). `randomize` is made deterministic by
/// injecting a `PermutationStrategy`.
@MainActor
final class PlayerCorePlaylistEditTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String, title: String? = nil) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"), title: title)
    }

    private func makeCore(
        engine: FakePlaybackEngine = FakePlaybackEngine(),
        permutation: ((Int) -> [Int])? = nil
    ) -> PlayerCore {
        PlayerCore(
            engine: engine,
            shuffleStrategy: PlayerCore.defaultShuffleStrategy,
            permutationStrategy: permutation ?? PlayerCore.defaultPermutationStrategy
        )
    }

    /// Load a/b/c/d and start playing index `playing`.
    private func loadedCore(
        engine: FakePlaybackEngine = FakePlaybackEngine(),
        names: [String] = ["a", "b", "c", "d"],
        playing: Int? = nil,
        permutation: ((Int) -> [Int])? = nil
    ) -> PlayerCore {
        let core = makeCore(engine: engine, permutation: permutation)
        core.load(names.map { track($0) })
        if let playing {
            core.select(playing)
        }
        return core
    }

    private func titles(of core: PlayerCore) -> [String] {
        core.playlist.map { $0.url.deletingPathExtension().lastPathComponent }
    }

    // MARK: - append

    func testAppendGrowsAtEndAndKeepsSelectionAndPlayback() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1)

        core.append([track("e"), track("f")])

        XCTAssertEqual(titles(of: core), ["a", "b", "c", "d", "e", "f"])
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 0)
    }

    /// Appending to an EMPTY list selects the first new row — SELECT ONLY,
    /// never auto-play (the adding-never-auto-plays contract holds). Without
    /// the selection, `play()`/`next()`/`previous()` (which guard on
    /// `currentIndex`) would all be dead over a visibly non-empty list.
    func testAppendToEmptySelectsFirstRowWithoutPlaying() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)

        core.append([track("a"), track("b")])

        XCTAssertEqual(core.playlist.count, 2)
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(engine.loadedURLs, [], "append must not touch the engine")
    }

    /// The payoff of the select-on-append-to-empty rule: ADD files to a fresh
    /// queue, press play — playback starts (before the fix, `play()` bailed on
    /// the nil `currentIndex` and nothing happened).
    func testAppendToEmptyThenPlayStartsPlayback() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)

        core.append([track("a"), track("b")])
        core.play()

        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "a.mp3")
        XCTAssertEqual(engine.playCount, 1)
    }

    func testAppendNothingIsNoOp() {
        let core = loadedCore(playing: 0)
        core.append([])
        XCTAssertEqual(core.playlist.count, 4)
        XCTAssertEqual(core.currentIndex, 0)
    }

    // MARK: - remove: rows BEFORE the current one shift it down

    func testRemoveBeforeCurrentShiftsCurrentDown() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 2)

        core.remove(at: [0])

        XCTAssertEqual(titles(of: core), ["b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1) // still "c"
        XCTAssertEqual(core.currentTrack?.url.lastPathComponent, "c.mp3")
        XCTAssertTrue(core.isPlaying) // playback untouched
        XCTAssertEqual(engine.stopCount, 0)
    }

    func testRemoveMultipleBeforeAndAfterCurrent() {
        let core = loadedCore(names: ["a", "b", "c", "d", "e"], playing: 2)

        core.remove(at: [0, 1, 4])

        XCTAssertEqual(titles(of: core), ["c", "d"])
        XCTAssertEqual(core.currentIndex, 0) // "c" shifted down by the two before it
        XCTAssertTrue(core.isPlaying)
    }

    func testRemoveAfterCurrentLeavesCurrentAlone() {
        let core = loadedCore(playing: 1)

        core.remove(at: [2, 3])

        XCTAssertEqual(titles(of: core), ["a", "b"])
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - remove: the CURRENT row stops playback + lands after the removal point

    func testRemoveCurrentStopsAndMovesToNextSurvivor() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1)

        core.remove(at: [1])

        XCTAssertEqual(titles(of: core), ["a", "c", "d"])
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
        // First surviving row after the removal point: old index 2 ("c"),
        // now at index 1.
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(core.currentTrack?.url.lastPathComponent, "c.mp3")
    }

    func testRemoveCurrentAtEndClampsToNewLastRow() {
        let core = loadedCore(playing: 3)

        core.remove(at: [3])

        XCTAssertEqual(titles(of: core), ["a", "b", "c"])
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(core.currentIndex, 2) // clamped to the new last row
    }

    func testRemoveCurrentPlusEarlierRowsLandsOnSurvivorAfterRemovalPoint() {
        let core = loadedCore(names: ["a", "b", "c", "d", "e"], playing: 2)

        core.remove(at: [0, 2])

        XCTAssertEqual(titles(of: core), ["b", "d", "e"])
        // Old current 2, one removed before it -> lands at 1 ("d", the first
        // survivor after the removal point).
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(core.currentTrack?.url.lastPathComponent, "d.mp3")
    }

    func testRemoveEverythingClearsSelectionAndStops() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 0)

        core.remove(at: [0, 1, 2, 3])

        XCTAssertTrue(core.playlist.isEmpty)
        XCTAssertNil(core.currentIndex)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testRemoveOutOfRangeIsIgnored() {
        let core = loadedCore(playing: 1)

        core.remove(at: [7, 99])
        core.remove(at: [])

        XCTAssertEqual(core.playlist.count, 4)
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying)
    }

    /// A paused (loaded, not playing) current row that is removed: the engine
    /// is stopped so it does not hold the vanished track, and a later play()
    /// LOADS the landing track fresh (not a stale resume).
    func testRemovePausedCurrentThenPlayLoadsLandingTrack() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1)
        core.pause()

        core.remove(at: [1])
        core.play()

        XCTAssertEqual(engine.lastLoadedURL?.lastPathComponent, "c.mp3")
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - crop

    func testCropKeepsOnlyTheGivenRows() {
        let core = loadedCore(names: ["a", "b", "c", "d", "e"], playing: 2)

        core.crop(to: [1, 2, 4])

        XCTAssertEqual(titles(of: core), ["b", "c", "e"])
        XCTAssertEqual(core.currentIndex, 1) // "c" followed
        XCTAssertTrue(core.isPlaying)
    }

    func testCropDroppingTheCurrentRowStopsAndLandsAfterRemovalPoint() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 0)

        core.crop(to: [2, 3])

        XCTAssertEqual(titles(of: core), ["c", "d"])
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(core.currentIndex, 0) // "c", the first survivor
    }

    func testCropToEmptyOrInvalidIsNoOp() {
        let core = loadedCore(playing: 1)

        core.crop(to: [])
        core.crop(to: [9, 42])

        XCTAssertEqual(core.playlist.count, 4)
        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - removeAll

    func testRemoveAllStopsAndEmptiesEverything() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 2)

        core.removeAll()

        XCTAssertTrue(core.playlist.isEmpty)
        XCTAssertNil(core.currentIndex)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testRemoveAllOnEmptyIsNoOp() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)

        core.removeAll()

        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertNil(core.currentIndex)
    }

    // MARK: - sort (title / filename): currentIndex follows the playing track

    func testSortByTitleFollowsPlayingTrackAndKeepsPlaying() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([
            track("1", title: "Zebra"),
            track("2", title: "apple"),
            track("3", title: "Mango")
        ])
        core.select(0) // playing "Zebra"

        core.sortByTitle()

        XCTAssertEqual(core.playlist.map(\.title), ["apple", "Mango", "Zebra"])
        XCTAssertEqual(core.currentIndex, 2) // "Zebra" followed to the end
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertEqual(engine.loadedURLs.count, 1) // no reload — audio untouched
    }

    func testSortByTitleFallsBackToFilenameForUntitledTracks() {
        let core = makeCore()
        core.load([track("zzz"), track("aaa", title: "The Middle")])

        core.sortByTitle()

        // "The Middle" (title) sorts before "zzz.mp3" (filename fallback).
        XCTAssertEqual(titles(of: core), ["aaa", "zzz"])
    }

    func testSortByFilenameIsCaseInsensitiveAndStable() {
        let core = makeCore()
        core.load([track("b"), track("A"), track("a"), track("C")])

        core.sortByFilename()

        // Case-insensitive keys; the equal "A"/"a" pair keeps original order.
        XCTAssertEqual(titles(of: core), ["A", "a", "b", "C"])
    }

    // MARK: - reverse

    func testReverseFollowsPlayingTrack() {
        let core = loadedCore(playing: 1)

        core.reverse()

        XCTAssertEqual(titles(of: core), ["d", "c", "b", "a"])
        XCTAssertEqual(core.currentIndex, 2) // "b" followed
        XCTAssertTrue(core.isPlaying)
    }

    /// Empty the list, re-fill it via append (which now selects row 0 — the
    /// select-on-append-to-empty rule), then reverse: the selection follows the
    /// selected (idle, not playing) track to its new position and nothing plays.
    func testReverseAfterEmptyThenAppendFollowsSelectedRow() {
        let core = makeCore()
        core.load([track("a"), track("b")])
        core.remove(at: [0, 1]) // empty the list, selection nil
        core.append([track("x"), track("y")]) // re-fill: selects "x" (row 0)

        core.reverse()

        XCTAssertEqual(titles(of: core), ["y", "x"])
        XCTAssertEqual(core.currentIndex, 1) // still "x", followed to its new row
        XCTAssertFalse(core.isPlaying)
    }

    // MARK: - randomize (injected permutation — deterministic)

    func testRandomizeAppliesInjectedPermutationAndFollowsPlayingTrack() {
        let core = loadedCore(
            playing: 0,
            permutation: { count in
                XCTAssertEqual(count, 4)
                return [2, 0, 3, 1] // new position -> old index
            }
        )

        core.randomize()

        XCTAssertEqual(titles(of: core), ["c", "a", "d", "b"])
        XCTAssertEqual(core.currentIndex, 1) // "a" followed
        XCTAssertTrue(core.isPlaying)
    }

    func testRandomizeWithMalformedPermutationIsNoOp() {
        let core = loadedCore(playing: 1, permutation: { _ in [0, 0, 1, 2] })

        core.randomize()

        XCTAssertEqual(titles(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testRandomizeWithWrongLengthPermutationIsNoOp() {
        let core = loadedCore(playing: 1, permutation: { _ in [0, 1] })

        core.randomize()

        XCTAssertEqual(titles(of: core), ["a", "b", "c", "d"])
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testDefaultPermutationStrategyIsAValidPermutation() {
        let permutation = PlayerCore.defaultPermutationStrategy(count: 8)
        XCTAssertEqual(permutation.sorted(), Array(0..<8))
    }

    // MARK: - reorder: paused resume stays on the same (followed) track

    func testReorderWhilePausedResumesTheSameTrackWithoutReload() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine: engine, playing: 1)
        core.pause()

        core.reverse() // "b" moves to index 2; loadedIndex follows too

        XCTAssertEqual(core.currentIndex, 2)
        core.play()
        // Resume, not reload: the engine still holds "b" from the original load.
        XCTAssertEqual(engine.loadedURLs.count, 1)
        XCTAssertTrue(core.isPlaying)
    }
}
