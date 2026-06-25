import Foundation
import XCTest
@testable import PlayerCore

/// Tests for `PlayerCore`, the pure transport + state layer. A `FakePlaybackEngine`
/// stands in for the real audio engine, so every command and every state
/// transition is asserted in memory.
///
/// Each `MARK` maps to one of the acceptance criteria (1...11). Shuffle is made
/// deterministic by injecting a `nextIndexStrategy` closure.
@MainActor
final class PlayerCoreTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    private func makeCore(
        engine: FakePlaybackEngine = FakePlaybackEngine(),
        shuffle strategy: ((_ count: Int, _ current: Int?) -> Int)? = nil
    ) -> PlayerCore {
        if let strategy {
            return PlayerCore(engine: engine, shuffleStrategy: strategy)
        }
        return PlayerCore(engine: engine)
    }

    // MARK: - 1. load sets playlist + selects index 0, no play

    func testLoadSetsPlaylistSelectsFirstAndDoesNotPlay() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b"), track("c")]

        core.load(tracks)

        XCTAssertEqual(core.playlist, tracks)
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(core.currentTrack, tracks[0])
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertTrue(engine.loadedURLs.isEmpty)
    }

    func testLoadEmptyClearsSelection() {
        let core = makeCore()
        core.load([track("a")])
        core.load([])

        XCTAssertTrue(core.playlist.isEmpty)
        XCTAssertNil(core.currentIndex)
        XCTAssertNil(core.currentTrack)
    }

    // MARK: - 2. play loads currentTrack + engine.play + isPlaying true

    func testPlayLoadsCurrentTrackAndPlays() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)

        core.play()

        XCTAssertEqual(engine.loadedURLs, [tracks[0].url])
        XCTAssertEqual(engine.playCount, 1)
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - 3. togglePlayPause toggles

    func testTogglePlayPauseTogglesState() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a")])

        core.togglePlayPause() // -> play
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.playCount, 1)

        core.togglePlayPause() // -> pause
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.pauseCount, 1)

        core.togglePlayPause() // -> play again
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.playCount, 2)
    }

    // MARK: - 4. next/previous move index and load+play the right track

    func testNextAdvancesAndPlays() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b"), track("c")]
        core.load(tracks)
        core.play()

        core.next()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.lastLoadedURL, tracks[1].url)
        XCTAssertTrue(core.isPlaying)
    }

    func testPreviousRetreatsAndPlays() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b"), track("c")]
        core.load(tracks)
        core.select(2)

        core.previous()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.lastLoadedURL, tracks[1].url)
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - 5. boundary: repeat .off next past last stops; .all wraps

    func testNextPastLastWithRepeatOffStops() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .off
        core.select(1) // last
        XCTAssertTrue(core.isPlaying)

        core.next()

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
        // Documented choice: selection clamps to the last track on stop.
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testNextPastLastWithRepeatAllWrapsToZero() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .all
        core.select(1) // last

        core.next()

        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.lastLoadedURL, tracks[0].url)
        XCTAssertTrue(core.isPlaying)
    }

    func testPreviousAtFirstWithRepeatOffStaysAtFirst() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .off
        core.play() // at index 0

        core.previous()

        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertTrue(core.isPlaying)
    }

    func testPreviousAtFirstWithRepeatAllWrapsToLast() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b"), track("c")]
        core.load(tracks)
        core.repeatMode = .all
        core.play() // at index 0

        core.previous()

        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertEqual(engine.lastLoadedURL, tracks[2].url)
    }

    // MARK: - 6. onPlaybackFinished: .one replays, .all wraps, .off advances/stops

    func testFinishedRepeatOneReplaysSameTrack() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .one
        core.select(1)
        let playsBefore = engine.playCount

        engine.fireFinished()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.lastLoadedURL, tracks[1].url)
        XCTAssertEqual(engine.playCount, playsBefore + 1)
        XCTAssertTrue(core.isPlaying)
    }

    func testFinishedRepeatAllAtLastWraps() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .all
        core.select(1)

        engine.fireFinished()

        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertTrue(core.isPlaying)
    }

    func testFinishedRepeatOffAdvances() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .off
        core.play() // index 0

        engine.fireFinished()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying)
    }

    func testFinishedRepeatOffAtLastStops() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.repeatMode = .off
        core.select(1) // last

        engine.fireFinished()

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.stopCount, 1)
    }

    // MARK: - 7. shuffle picks injected index, stays in range, safe on small lists

    func testShuffleNextPicksForcedIndex() {
        let engine = FakePlaybackEngine()
        var forced = 3
        let core = makeCore(engine: engine) { _, _ in forced }
        let tracks = [track("a"), track("b"), track("c"), track("d")]
        core.load(tracks)
        core.isShuffle = true
        core.play()

        core.next()
        XCTAssertEqual(core.currentIndex, 3)
        XCTAssertEqual(engine.lastLoadedURL, tracks[3].url)

        forced = 1
        core.next()
        XCTAssertEqual(core.currentIndex, 1)
    }

    func testShuffleSingleTrackDoesNotCrash() {
        let engine = FakePlaybackEngine()
        // Strategy returns the same index; core must not deadlock/crash.
        let core = makeCore(engine: engine) { _, current in current ?? 0 }
        core.load([track("only")])
        core.isShuffle = true
        core.play()

        core.next() // should be a safe no-op (stays on the only track)
        XCTAssertEqual(core.currentIndex, 0)
    }

    func testShuffleEmptyPlaylistDoesNotCrash() {
        let core = makeCore { _, _ in 0 }
        core.isShuffle = true
        core.next() // no-op, must not crash
        XCTAssertNil(core.currentIndex)
    }

    func testDefaultShuffleStrategyStaysInRange() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine) // default Int.random-based strategy
        let tracks = [track("a"), track("b"), track("c")]
        core.load(tracks)
        core.isShuffle = true
        core.play()

        for _ in 0..<50 {
            core.next()
            let idx = core.currentIndex!
            XCTAssertTrue((0..<tracks.count).contains(idx))
        }
    }

    // MARK: - 8. play when engine.load throws skips to next playable; all-unplayable stops

    func testPlaySkipsUnplayableTrack() {
        let engine = FakePlaybackEngine()
        let tracks = [track("bad"), track("good")]
        engine.unloadableURLs = [tracks[0].url]
        let core = makeCore(engine: engine)
        core.load(tracks)

        core.play()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.lastLoadedURL, tracks[1].url)
        XCTAssertTrue(core.isPlaying)
    }

    func testPlayAllUnplayableStops() {
        let engine = FakePlaybackEngine()
        let tracks = [track("bad1"), track("bad2")]
        engine.unloadableURLs = [tracks[0].url, tracks[1].url]
        let core = makeCore(engine: engine)
        core.load(tracks)

        core.play()

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertTrue(engine.stopCount >= 1)
    }

    // MARK: - 9. setVolume clamps and sets engine.volume

    func testSetVolumeClampsLow() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.setVolume(-1)
        XCTAssertEqual(core.volume, 0)
        XCTAssertEqual(engine.volume, 0)
    }

    func testSetVolumeClampsHigh() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.setVolume(2)
        XCTAssertEqual(core.volume, 1)
        XCTAssertEqual(engine.volume, 1)
    }

    func testSetVolumeMidRange() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.setVolume(0.5)
        XCTAssertEqual(core.volume, 0.5)
        XCTAssertEqual(engine.volume, 0.5)
    }

    // MARK: - 10. empty playlist: play/next/previous/seek are safe no-ops

    func testEmptyPlaylistCommandsAreNoOps() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)

        core.play()
        core.next()
        core.previous()
        core.seek(to: 10)

        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertNil(core.currentIndex)
        // seek still delegates even with no playlist (engine guards itself).
        XCTAssertEqual(engine.seekedTimes, [10])
    }

    // MARK: - 11. select out of range guarded; in range loads+plays

    func testSelectOutOfRangeIsNoOp() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a"), track("b")])

        core.select(5)
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.playCount, 0)

        core.select(-1)
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.playCount, 0)
    }

    func testSelectInRangeLoadsAndPlays() {
        let engine = FakePlaybackEngine()
        let tracks = [track("a"), track("b"), track("c")]
        let core = makeCore(engine: engine)
        core.load(tracks)

        core.select(2)
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertEqual(engine.lastLoadedURL, tracks[2].url)
        XCTAssertTrue(core.isPlaying)
    }

    // MARK: - Delegation: currentTime / duration / seek / pause

    func testCurrentTimeAndDurationDelegateToEngine() {
        let engine = FakePlaybackEngine()
        engine.currentTime = 12.5
        engine.duration = 200
        let core = makeCore(engine: engine)

        XCTAssertEqual(core.currentTime, 12.5)
        XCTAssertEqual(core.duration, 200)
    }

    func testSeekDelegatesToEngine() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a")])
        core.play()

        core.seek(to: 42)
        XCTAssertEqual(engine.seekedTimes, [42])
    }

    func testPausePausesEngine() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a")])
        core.play()

        core.pause()
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.pauseCount, 1)
    }
}
