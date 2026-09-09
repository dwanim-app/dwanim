import Foundation
import XCTest
@testable import PlayerCore

/// Pins what happens to navigation when a track **opens but delivers no audio**.
///
/// ## The defect this file exists for
/// `playCurrent()` only ever treated a track as unplayable when
/// `engine.load(_:)` THREW. A file that loads successfully and then drains
/// instantly — reporting a natural finish before a single frame has been
/// rendered — never reached the recovery walk at all. It reached
/// `handlePlaybackFinished` instead, and auto-advance took over:
///
/// ```
/// queue: t0 t1 t2 [t3 = opens, plays nothing] t4 t5 t6   repeat .off, on t4
/// ◀◀ -> 3, loads fine, finishes at once -> auto-advance -> 4   (back where we started)
/// ◀◀ -> 3, ... for ever.  t0…t2 are unreachable with ◀◀.
/// ```
///
/// Under `.one` it was worse: the instant finish replayed the same silent track,
/// so `◀◀` onto it parked the listener on silence permanently.
///
/// This is not hypothetical. An Ogg-wrapped FLAC (`.flac.oga`) opens on macOS,
/// reports 44100 Hz / 2 ch / 100.5 s for an 8-second clip, and its scheduled
/// segment completes ~18 ms after `play()`. `RealQueueTransportClickThroughTests`
/// drives that exact file; this file is its deterministic twin.
///
/// ## The rule these tests pin
/// A natural finish that arrives **within `silentFinishWindow` of the track
/// starting**, on a track that had promised **more than `silentFinishMinimumPromise`
/// of audio**, is not a finish at all — it is an unplayable track. The core then
/// keeps walking the way the press pointed, exactly as it does for a load that
/// threw. Everything else about auto-advance is untouched: a plausible finish
/// still replays under `.one`, wraps under `.all`, and stops at the end under
/// `.off`.
@MainActor
final class PlayerCoreSilentTrackNavigationTests: XCTestCase {

    // MARK: - Fixtures

    /// A clock the test drives by hand, so "the finish arrived too fast to be
    /// real" is asserted deterministically instead of by sleeping.
    private final class TestClock {
        private(set) var seconds: TimeInterval = 10_000
        func read() -> TimeInterval { seconds }
        func advance(_ delta: TimeInterval) { seconds += delta }
    }

    private func track(_ name: String) -> Track {
        Track(url: URL(fileURLWithPath: "/music/\(name).mp3"))
    }

    /// A queue of `count` tracks that each CLAIM `promise` seconds of audio — the
    /// ordinary case, so the silent verdict has to come from the timing and not
    /// from a zero duration.
    private func makeCore(
        _ engine: FakePlaybackEngine,
        clock: TestClock,
        tracks count: Int,
        promise: TimeInterval = 100
    ) -> PlayerCore {
        let list = (0..<count).map { track("t\($0)") }
        engine.durations = Dictionary(uniqueKeysWithValues: list.map { ($0.url, promise) })
        let core = PlayerCore(
            engine: engine,
            shuffleStrategy: PlayerCore.defaultShuffleStrategy,
            now: clock.read
        )
        core.load(list)
        return core
    }

    /// The engine callback arriving `after` seconds — the fake's stand-in for the
    /// real engine's `DispatchQueue.main.async` hop out of the audio thread.
    private func finish(_ engine: FakePlaybackEngine, on clock: TestClock, after: TimeInterval) {
        clock.advance(after)
        engine.fireFinished()
    }

    /// How fast the real `.flac.oga` drains: measured at ~18 ms after `play()`.
    private static let instant: TimeInterval = 0.018

    /// Let the engine say whatever it would say in the moments after a press.
    ///
    /// ONLY a silent row reports anything — it drains at once and fires the
    /// finish callback. A row that really plays says nothing for minutes, which
    /// is why a live row must never be handed a `fireFinished()` here. The loop
    /// keeps going while the core lands on another silent row, and its bound is
    /// the failure mode under test: an unbounded walk would spin for ever.
    @discardableResult
    private func settle(
        _ engine: FakePlaybackEngine,
        _ core: PlayerCore,
        clock: TestClock,
        silent: Set<URL>
    ) -> Int {
        var deliveries = 0
        while let url = core.currentTrack?.url, silent.contains(url), core.isPlaying, deliveries < 32 {
            finish(engine, on: clock, after: Self.instant)
            deliveries += 1
        }
        XCTAssertLessThan(deliveries, 32, "the silent-file walk did not terminate")
        return deliveries
    }

    // MARK: - The reported defect

    /// `◀◀` onto a track that opens and delivers nothing keeps walking BACK.
    /// Before the fix the listener was bounced forward to the track they had
    /// just left, and rows before the silent one were unreachable with `◀◀`.
    func testPreviousOntoASilentTrackKeepsWalkingBackInsteadOfBouncingForward() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 7)
        core.repeatMode = .off
        core.select(4)

        core.previous()
        XCTAssertEqual(core.currentIndex, 3, "the press landed on the silent track (it loads fine)")

        settle(engine, core, clock: clock, silent: [track("t3").url])

        XCTAssertEqual(core.currentIndex, 2, "the instant finish is a dead file: keep walking BACK")
        XCTAssertEqual(core.currentTrack, track("t2"))
        XCTAssertTrue(core.isPlaying)
    }

    /// Repeated `◀◀` over a silent row reaches the front of the queue. The
    /// pre-fix trail for the same run was `[3, 4, 3, 4, …]`.
    func testRepeatedPreviousOverASilentRowReachesTheFrontOfTheQueue() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 7)
        core.repeatMode = .off
        core.select(4)

        var trail: [Int] = []
        for _ in 1...4 {
            core.previous()
            settle(engine, core, clock: clock, silent: [track("t3").url])
            trail.append(core.currentIndex ?? -1)
        }

        XCTAssertEqual(trail, [2, 1, 0, 0],
                       "4 -> (3 is silent) -> 2 -> 1 -> 0, then restart t0 in place")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(core.currentTrack, track("t0"))
    }

    /// Under `.one` a silent track used to hold the listener for ever, replaying
    /// silence. It must be skipped like any other unplayable file — in the
    /// direction the press pointed.
    func testRepeatOneDoesNotStickForeverReplayingASilentTrack() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 7)
        core.repeatMode = .one
        core.select(4)

        core.previous()
        XCTAssertEqual(core.currentIndex, 3)

        settle(engine, core, clock: clock, silent: [track("t3").url])

        XCTAssertEqual(core.currentIndex, 2, "`.one` must not replay a track that plays nothing")
        XCTAssertTrue(core.isPlaying)
    }

    /// `▶▶` over the same silent row still walks FORWARD — the direction rule is
    /// the press's, not the file's.
    func testNextOntoASilentTrackKeepsWalkingForward() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 7)
        core.repeatMode = .off
        core.select(2)

        core.next()
        XCTAssertEqual(core.currentIndex, 3)

        settle(engine, core, clock: clock, silent: [track("t3").url])

        XCTAssertEqual(core.currentIndex, 4, "2 -> (3 is silent) -> 4")
        XCTAssertTrue(core.isPlaying)
    }

    /// A queue in which NOTHING renders comes to rest instead of sweeping the
    /// list for ever under `.all`.
    func testAQueueOfNothingButSilentTracksComesToRest() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3)
        core.repeatMode = .all
        let everything: Set<URL> = Set((0..<3).map { track("t\($0)").url })
        core.select(0)

        let deliveries = settle(engine, core, clock: clock, silent: everything)

        XCTAssertEqual(deliveries, 3, "each row was tried exactly once — no sweeping round")
        XCTAssertFalse(core.isPlaying, "the walk came to rest rather than looping the queue")
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }

    // MARK: - Auto-advance is otherwise untouched

    /// A finish that took as long as the track is long is an ORDINARY finish:
    /// `.off` advances to the next row.
    func testAPlausibleFinishStillAutoAdvancesUnderRepeatOff() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3)
        core.repeatMode = .off
        core.select(0)

        finish(engine, on: clock, after: 100)

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying)
    }

    /// ...and `.one` still replays the SAME track.
    func testAPlausibleFinishStillReplaysUnderRepeatOne() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3)
        core.repeatMode = .one
        core.select(1)
        engine.resetRecordedCalls()

        finish(engine, on: clock, after: 100)

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.loadedURLs, [track("t1").url], "the same track was reloaded")
        XCTAssertTrue(core.isPlaying)
    }

    /// ...and `.all` still wraps off the end.
    func testAPlausibleFinishStillWrapsUnderRepeatAll() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3)
        core.repeatMode = .all
        core.select(2)

        finish(engine, on: clock, after: 100)

        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertTrue(core.isPlaying)
    }

    /// ...and `.off` at the last row still stops.
    func testAPlausibleFinishStillStopsAtTheEndUnderRepeatOff() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3)
        core.repeatMode = .off
        core.select(2)

        finish(engine, on: clock, after: 100)

        XCTAssertEqual(core.currentIndex, 2, "the selection clamps to the last track")
        XCTAssertFalse(core.isPlaying)
    }

    // MARK: - The verdict must not fire on legitimately short audio

    /// A jingle really IS half a second long. Finishing fast is not suspicious
    /// when the track never promised more, so it auto-advances normally.
    func testAGenuinelyShortTrackFinishingFastIsNotTreatedAsSilent() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3, promise: 0.5)
        core.repeatMode = .one
        core.select(1)
        engine.resetRecordedCalls()

        finish(engine, on: clock, after: 0.02)

        XCTAssertEqual(core.currentIndex, 1, "a short track still repeats under `.one`")
        XCTAssertEqual(engine.loadedURLs, [track("t1").url])
        XCTAssertTrue(core.isPlaying)
    }

    /// Seeking to just before the end legitimately produces a finish moments
    /// later. The promise is measured from where playback actually resumes, so
    /// the seek cannot be mistaken for silence.
    func testSeekingCloseToTheEndIsNotMistakenForSilence() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let core = makeCore(engine, clock: clock, tracks: 3)
        core.repeatMode = .off
        core.select(0)
        core.seek(to: 99.9)                       // 0.1 s of audio left of 100

        finish(engine, on: clock, after: 0.05)

        XCTAssertEqual(core.currentIndex, 1, "an honest end-of-track after a seek still advances")
        XCTAssertTrue(core.isPlaying)
    }

    /// While shuffling, the recovery from a silent row steps LINEARLY — it is a
    /// repair, not a pick — exactly as the failed-load recovery already does.
    /// Pinned so the choice is deliberate rather than incidental.
    ///
    /// The strategy here always names t2, which is the silent row: a recovery
    /// that consulted it again would land back on silence and come to rest,
    /// whereas the linear step lands on the playable t3.
    func testRecoveryFromASilentTrackStepsLinearlyEvenWhileShuffling() {
        let engine = FakePlaybackEngine()
        let clock = TestClock()
        let list = (0..<5).map { track("t\($0)") }
        engine.durations = Dictionary(uniqueKeysWithValues: list.map { ($0.url, 100) })
        let core = PlayerCore(
            engine: engine,
            shuffleStrategy: { _, _ in 2 },
            now: clock.read
        )
        core.load(list)
        core.isShuffle = true
        core.select(0)

        core.next()
        XCTAssertEqual(core.currentIndex, 2, "the shuffle strategy chose t2")

        settle(engine, core, clock: clock, silent: [track("t2").url])

        XCTAssertEqual(core.currentIndex, 3, "recovery stepped linearly to t3, it did not re-pick")
        XCTAssertTrue(core.isPlaying)
    }
}
