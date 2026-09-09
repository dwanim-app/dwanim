import Foundation
import XCTest
@testable import PlayerCore

/// Pins the EXPLICIT-NAVIGATION contract for `.one`.
///
/// ## History (why this file was rewritten, not deleted)
/// The `PlayerCore` header once promised "explicit `next`/`previous` always move
/// to a different track". That promise was false at BOTH ends of the queue, and an
/// earlier revision of this file pinned the code as it then stood: `.one` behaved
/// EXACTLY like `.off` for explicit skips, so `▶▶` on the last track stopped even
/// with Repeat lit. Because the Cadence Repeat button was a 2-state `off` ↔ `.one`
/// toggle, `.all` — the only wrapping mode — was unreachable from the default UI,
/// and the button therefore looked dead at the end of the queue.
///
/// The owner resolved that open product decision: **explicit navigation wraps
/// whenever repeat is ON**, i.e. for `.all` AND `.one`. This file now pins the NEW
/// truth, end to end:
///
/// - `next` on the LAST track wraps to the first when `repeatMode` is `.all` or
///   `.one`; only `.off` stops there.
/// - `previous` on the FIRST track wraps to the last when `repeatMode` is `.all`
///   or `.one`; only `.off` restarts that track in place.
/// - Mid-list, `.one` still steps to the neighbour (never a replay in place).
/// - AUTO-ADVANCE is untouched: `onPlaybackFinished` under `.one` still replays
///   the SAME track — wrapping is an EXPLICIT-navigation rule only.
/// - The `.off` asymmetry (stop at the end, restart at the front) is a DELIBERATE
///   industry-convention keep, asserted here so a future "symmetry" refactor
///   cannot quietly change it.
@MainActor
final class PlayerCoreRepeatOneNavigationTests: XCTestCase {

    // MARK: - Fixtures

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    private func loadedCore(_ engine: FakePlaybackEngine, repeatMode: RepeatMode,
                            playing index: Int) -> PlayerCore {
        let core = PlayerCore(engine: engine)
        core.load([track("a"), track("b"), track("c")])
        core.repeatMode = repeatMode
        core.select(index)
        return core
    }

    // MARK: - next at the LAST track

    /// The headline change: `.one` at the end WRAPS to the first track and plays
    /// it, rather than stopping. Nothing is stopped, and track "a" is loaded.
    func testNextAtLastTrackWithRepeatOneWrapsToFirstTrack() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine, repeatMode: .one, playing: 2)
        let stopsBefore = engine.stopCount

        core.next()

        XCTAssertEqual(core.currentIndex, 0, "explicit next wraps to the first track under .one")
        XCTAssertTrue(core.isPlaying, "the wrapped-to track plays")
        XCTAssertEqual(engine.lastLoadedURL, core.playlist[0].url, "track a is loaded")
        XCTAssertEqual(engine.stopCount, stopsBefore, "nothing is stopped")
    }

    /// The equivalence that now holds: for explicit `next` at the end, `.one` and
    /// `.all` behave IDENTICALLY (both wrap), and `.off` is the sole outlier that
    /// stops. This is the inverse of the equivalence this file used to assert.
    func testNextAtLastTrackTreatsRepeatOneExactlyLikeRepeatAll() {
        let allEngine = FakePlaybackEngine()
        let allCore = loadedCore(allEngine, repeatMode: .all, playing: 2)
        let oneEngine = FakePlaybackEngine()
        let oneCore = loadedCore(oneEngine, repeatMode: .one, playing: 2)

        allCore.next()
        oneCore.next()

        XCTAssertEqual(oneCore.currentIndex, allCore.currentIndex)
        XCTAssertEqual(oneCore.isPlaying, allCore.isPlaying)
        XCTAssertEqual(oneEngine.loadedURLs, allEngine.loadedURLs)
        XCTAssertEqual(oneEngine.stopCount, allEngine.stopCount)
        XCTAssertEqual(oneCore.currentIndex, 0)

        // ...and `.off` is the ONLY mode where explicit next stops at the end.
        let offEngine = FakePlaybackEngine()
        let offCore = loadedCore(offEngine, repeatMode: .off, playing: 2)
        let offLoadsBefore = offEngine.loadedURLs.count
        offCore.next()
        XCTAssertEqual(offCore.currentIndex, 2, "with repeat off the selection clamps to the last track")
        XCTAssertFalse(offCore.isPlaying, "with repeat off, next at the end stops")
        XCTAssertEqual(offEngine.loadedURLs.count, offLoadsBefore, "with repeat off nothing new is loaded")
        XCTAssertEqual(offEngine.stopCount, 1)
    }

    // MARK: - previous at the FIRST track

    /// The symmetric half: `.one` at the front WRAPS to the last track rather than
    /// restarting the first one in place.
    func testPreviousAtFirstTrackWithRepeatOneWrapsToLastTrack() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine, repeatMode: .one, playing: 0)

        core.previous()

        XCTAssertEqual(core.currentIndex, 2, "explicit previous wraps to the last track under .one")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.lastLoadedURL, core.playlist[2].url, "it loads track c, not track a")
    }

    func testPreviousAtFirstTrackTreatsRepeatOneExactlyLikeRepeatAll() {
        let allEngine = FakePlaybackEngine()
        let allCore = loadedCore(allEngine, repeatMode: .all, playing: 0)
        let oneEngine = FakePlaybackEngine()
        let oneCore = loadedCore(oneEngine, repeatMode: .one, playing: 0)

        allCore.previous()
        oneCore.previous()

        XCTAssertEqual(oneCore.currentIndex, allCore.currentIndex)
        XCTAssertEqual(oneCore.isPlaying, allCore.isPlaying)
        XCTAssertEqual(oneEngine.loadedURLs, allEngine.loadedURLs)
        XCTAssertEqual(oneCore.currentIndex, 2)

        // ...and `.off` is the ONLY mode that restarts the first track in place.
        let offEngine = FakePlaybackEngine()
        let offCore = loadedCore(offEngine, repeatMode: .off, playing: 0)
        offCore.previous()
        XCTAssertEqual(offCore.currentIndex, 0, "with repeat off the selection stays on the first track")
        XCTAssertEqual(offEngine.lastLoadedURL, offCore.playlist[0].url, "it reloads track a — a restart")
        XCTAssertTrue(offCore.isPlaying)
    }

    // MARK: - the DELIBERATE `.off` asymmetry (do not "fix")

    /// `.off` is asymmetric ON PURPOSE — `next` at the end STOPS while `previous`
    /// at the front RESTARTS — matching Music / iTunes / Spotify. Asserted as a
    /// pair so a future symmetry refactor has to argue with a red test.
    func testRepeatOffKeepsItsDeliberateEndAsymmetry() {
        let endEngine = FakePlaybackEngine()
        let endCore = loadedCore(endEngine, repeatMode: .off, playing: 2)
        endCore.next()
        XCTAssertFalse(endCore.isPlaying, "next at the end stops")
        XCTAssertEqual(endCore.currentIndex, 2)

        let frontEngine = FakePlaybackEngine()
        let frontCore = loadedCore(frontEngine, repeatMode: .off, playing: 0)
        let playsBefore = frontEngine.playCount
        frontCore.previous()
        XCTAssertTrue(frontCore.isPlaying, "previous at the front restarts rather than stopping")
        XCTAssertEqual(frontCore.currentIndex, 0)
        XCTAssertEqual(frontEngine.playCount, playsBefore + 1)
    }

    // MARK: - mid-list

    /// Unchanged: mid-list, `.one` never replays the current track on an explicit
    /// skip — it steps to the neighbour, so a listener with Repeat on can still
    /// navigate through the queue.
    func testMidListRepeatOneStepsToTheNeighbourRatherThanReplaying() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine, repeatMode: .one, playing: 1)

        core.next()
        XCTAssertEqual(core.currentIndex, 2, "explicit next moves off the current track under .one")
        XCTAssertEqual(engine.lastLoadedURL, core.playlist[2].url)

        core.previous()
        XCTAssertEqual(core.currentIndex, 1, "explicit previous moves off it too")
        XCTAssertEqual(engine.lastLoadedURL, core.playlist[1].url)
    }

    // MARK: - auto-advance is NOT explicit navigation

    /// The wrap rule is EXPLICIT-navigation only. When the engine reports the
    /// track finished under `.one`, the SAME track replays — even on the last
    /// track, where explicit `next` would now wrap to the first. This is the
    /// boundary that keeps repeat-one meaning "repeat this one".
    func testFinishedUnderRepeatOneStillReplaysTheSameTrackAtTheEndOfTheQueue() {
        let engine = FakePlaybackEngine()
        let core = loadedCore(engine, repeatMode: .one, playing: 2)
        let playsBefore = engine.playCount

        engine.fireFinished()

        XCTAssertEqual(core.currentIndex, 2, "auto-advance under .one does NOT wrap")
        XCTAssertEqual(engine.lastLoadedURL, core.playlist[2].url, "the same track is reloaded")
        XCTAssertEqual(engine.playCount, playsBefore + 1)
        XCTAssertTrue(core.isPlaying)
    }

    /// The other two auto-advance semantics, pinned alongside so the trio is
    /// asserted together: `.all` wraps on finish, `.off` stops at the end.
    func testFinishedUnderRepeatAllWrapsAndUnderRepeatOffStops() {
        let allEngine = FakePlaybackEngine()
        let allCore = loadedCore(allEngine, repeatMode: .all, playing: 2)
        allEngine.fireFinished()
        XCTAssertEqual(allCore.currentIndex, 0, ".all wraps on finish")
        XCTAssertTrue(allCore.isPlaying)

        let offEngine = FakePlaybackEngine()
        let offCore = loadedCore(offEngine, repeatMode: .off, playing: 2)
        offEngine.fireFinished()
        XCTAssertEqual(offCore.currentIndex, 2, ".off stays put")
        XCTAssertFalse(offCore.isPlaying, ".off stops at the end")
    }

    // MARK: - single-track queues

    /// A 1-track queue with repeat ON: the only track is both first and last, so
    /// both explicit skips wrap onto it and RESTART it. That is an observable
    /// action (the track starts over), which is why `canGoNext` stays true there.
    func testSingleTrackQueueWithRepeatOnRestartsOnBothSkips() {
        let engine = FakePlaybackEngine()
        let core = PlayerCore(engine: engine)
        core.load([track("solo")])
        core.repeatMode = .one
        core.select(0)
        let playsBefore = engine.playCount

        core.next()
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.playCount, playsBefore + 1, "next restarts the only track")

        core.previous()
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.playCount, playsBefore + 2, "previous restarts it too")
        XCTAssertTrue(core.isPlaying)
    }
}
