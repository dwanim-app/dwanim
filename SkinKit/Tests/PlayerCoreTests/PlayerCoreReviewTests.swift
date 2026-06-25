import Foundation
import XCTest
@testable import PlayerCore

/// Adversarial completeness review for `PlayerCore`'s transport state machine.
///
/// These tests probe state-machine interactions that the original 29-test suite
/// did not cover. They are written by an independent QA agent and intentionally
/// do NOT modify `Sources/` or the existing tests.
///
/// Test naming convention:
/// - `pin_…`   : pins / documents the *current* behavior (passes today). These
///               guard against silent regressions of a deliberate choice.
/// - `gap_…`   : asserts the behavior a correct transport state machine *should*
///               have. A FAILURE here documents a real gap/bug in the core.
///
/// Each `gap_` failure is annotated with a `[MUST-FIX]` or `[FYI]` tag in the
/// failure message so the tech-lead report maps 1:1 to a test.
@MainActor
final class PlayerCoreReviewTests: XCTestCase {

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

    // =========================================================================
    // MARK: - #1 play() idempotency / resume-after-pause
    // =========================================================================

    /// Probe: calling `play()` while already playing reloads + restarts the same
    /// track (it is NOT a no-op). Pins the current behavior so the team can
    /// decide whether the redundant reload is acceptable.
    func test_pin_playWhileAlreadyPlaying_reloadsAndRestartsCurrentTrack() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)

        core.play()
        XCTAssertEqual(engine.loadedURLs, [tracks[0].url])
        XCTAssertEqual(engine.playCount, 1)

        core.play() // already playing

        // Current behavior: a second load + play of the SAME track.
        XCTAssertEqual(engine.loadedURLs, [tracks[0].url, tracks[0].url],
                       "play() while playing re-loads the same track (observed).")
        XCTAssertEqual(engine.playCount, 2)
        XCTAssertTrue(core.isPlaying)
    }

    /// [MUST-FIX] Resume after pause must NOT reload the track from the start.
    ///
    /// Real-world bug: pause at 90s, then play() -> the user expects to resume at
    /// 90s. `playCurrent()` unconditionally calls `engine.load(url)` which (in a
    /// real engine) resets position to 0. We detect the reload by counting
    /// load(_:) calls for the current url: a true resume issues NO new load.
    func test_gap_playAfterPause_shouldResumeNotReloadFromStart() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a")])

        core.play()
        XCTAssertEqual(engine.loadedURLs.count, 1)

        // Simulate elapsed playback then pause.
        engine.currentTime = 90
        core.pause()
        XCTAssertFalse(core.isPlaying)

        core.play() // resume

        XCTAssertEqual(engine.loadedURLs.count, 1,
                       "[MUST-FIX] resume after pause re-loads the file (load count went to \(engine.loadedURLs.count)), which restarts the track from 0 instead of resuming. A real engine resets currentTime on load.")
        XCTAssertTrue(core.isPlaying)
    }

    // =========================================================================
    // MARK: - #2 load() while playing
    // =========================================================================

    /// [MUST-FIX] Loading a new playlist while playing leaves the core in an
    /// inconsistent state: the engine is never stopped and `isPlaying` stays
    /// true, but the new playlist's track 0 is NOT loaded (load does not
    /// auto-play). Result: `isPlaying == true` while nothing from the new
    /// playlist is loaded, and the OLD track is still running in the engine.
    func test_gap_loadWhilePlaying_shouldStopEngineAndResetIsPlaying() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("old1"), track("old2")])
        core.play()
        XCTAssertTrue(core.isPlaying)
        let stopsBefore = engine.stopCount

        core.load([track("new1"), track("new2")])

        // Inconsistent state today: isPlaying still true, engine not stopped,
        // yet the new track was never loaded.
        XCTAssertFalse(core.isPlaying,
                       "[MUST-FIX] load() while playing leaves isPlaying == true even though the new playlist's track is not loaded and the engine still holds the old track.")
        XCTAssertGreaterThan(engine.stopCount, stopsBefore,
                             "[MUST-FIX] load() while playing does not stop the engine; the previous track keeps playing under the new playlist.")
    }

    /// Pin: load() resets selection to index 0 of the new playlist (this part is
    /// correct and tested implicitly elsewhere; pinned here next to the gap).
    func test_pin_loadResetsSelectionToZeroOfNewPlaylist() {
        let core = makeCore()
        core.load([track("old1"), track("old2")])
        core.select(1)
        core.load([track("new1"), track("new2"), track("new3")])
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(core.currentTrack, track("new1"))
    }

    // =========================================================================
    // MARK: - #3 onPlaybackFinished late/odd callbacks
    // =========================================================================

    /// Pin: a finished callback with an empty playlist is a safe no-op (guarded).
    func test_pin_finishedOnEmptyPlaylist_isSafeNoOp() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)

        engine.fireFinished() // never loaded anything

        XCTAssertNil(core.currentIndex)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(engine.stopCount, 0)
    }

    /// Pin: a finished callback after the playlist was cleared (a late callback
    /// arriving after load([])) is a safe no-op and does not crash.
    func test_pin_finishedAfterPlaylistCleared_isSafeNoOp() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a")])
        core.play()
        core.load([]) // clears selection

        engine.fireFinished() // late callback

        XCTAssertNil(core.currentIndex)
    }

    // =========================================================================
    // MARK: - #4 shuffle + repeat combinations
    // =========================================================================

    /// Pin: `onPlaybackFinished` DOES honor shuffle (finished -> next -> shuffle
    /// branch). Forced strategy proves the finished path consults the strategy.
    func test_pin_finishedHonorsShuffle() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine) { _, _ in 2 }
        let tracks = [track("a"), track("b"), track("c"), track("d")]
        core.load(tracks)
        core.isShuffle = true
        core.repeatMode = .all
        core.play() // index 0

        engine.fireFinished()

        XCTAssertEqual(core.currentIndex, 2,
                       "finished should advance via the shuffle strategy when isShuffle is on.")
        XCTAssertEqual(engine.lastLoadedURL, tracks[2].url)
    }

    /// Pin (potential design smell): shuffle + `.off` never stops at the end of
    /// the playlist. With shuffle on, `next()` returns from the shuffle branch
    /// before reaching the `.off` end-of-list stop logic, so playback shuffles
    /// forever and `.off` is effectively ignored while shuffling. Pinned so the
    /// team confirms this is intended.
    func test_pin_shuffleWithRepeatOff_neverStops_shufflesForever() {
        let engine = FakePlaybackEngine()
        // Strategy always lands on the last index; classic "off + at last".
        let tracks = [track("a"), track("b")]
        let core = makeCore(engine: engine) { count, _ in count - 1 }
        core.load(tracks)
        core.isShuffle = true
        core.repeatMode = .off
        core.select(0)

        core.next() // strategy -> last index (1), still plays, does not stop

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertTrue(core.isPlaying,
                      "Observed: shuffle ignores .off end-of-list stop; it keeps playing.")
        XCTAssertEqual(engine.stopCount, 0,
                       "Observed: .off does not stop while shuffling.")
    }

    /// Pin: shuffle's no-op guard — when the strategy returns the current index,
    /// `next()` is a no-op (no reload, no stop). Documented for 1-track lists but
    /// also fires for any strategy that returns `current`.
    func test_pin_shuffleStrategyReturningCurrent_isNoOp() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine) { _, current in current ?? 0 }
        let tracks = [track("a"), track("b"), track("c")]
        core.load(tracks)
        core.isShuffle = true
        core.select(1)
        let loadsBefore = engine.loadedURLs.count

        core.next() // strategy returns 1 == current -> no-op

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(engine.loadedURLs.count, loadsBefore,
                       "shuffle next() is a no-op when the strategy returns the current index.")
    }

    // =========================================================================
    // MARK: - #5 seek clamping
    // =========================================================================

    /// Pin: negative seek is passed through to the engine unguarded. Pinned, not
    /// flagged: per brief, pass-through may be acceptable — but it IS undocumented
    /// and untested, so we pin it as observed behavior.
    func test_pin_seekNegative_passesThroughUnclamped() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a")])
        core.play()

        core.seek(to: -5)

        XCTAssertEqual(engine.seekedTimes, [-5],
                       "Observed: negative seek is forwarded to the engine without clamping.")
    }

    /// Pin: seeking beyond duration is passed through unguarded.
    func test_pin_seekBeyondDuration_passesThroughUnclamped() {
        let engine = FakePlaybackEngine()
        engine.duration = 100
        let core = makeCore(engine: engine)
        core.load([track("a")])
        core.play()

        core.seek(to: 999)

        XCTAssertEqual(engine.seekedTimes, [999],
                       "Observed: seek past duration is forwarded unclamped.")
    }

    // =========================================================================
    // MARK: - #6 previous semantics vs elapsed time
    // =========================================================================

    /// Pin: `previous()` always steps to the prior track regardless of elapsed
    /// time (it does NOT implement the "restart current if >Ns elapsed" pattern).
    /// Confirms the chosen behavior is consistent.
    func test_pin_previousAlwaysSteps_ignoringElapsedTime() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b"), track("c")]
        core.load(tracks)
        core.select(2)
        engine.currentTime = 30 // well past any "restart" threshold

        core.previous()

        XCTAssertEqual(core.currentIndex, 1,
                       "previous() steps to the prior track regardless of elapsed time.")
        XCTAssertEqual(engine.lastLoadedURL, tracks[1].url)
    }

    // =========================================================================
    // MARK: - #7 select while paused
    // =========================================================================

    /// Pin: `select()` forces playback to start even when the core was paused.
    /// This is a deliberate-looking choice (select == "play this now") but is
    /// undocumented and untested; pinned so a change is caught.
    func test_pin_selectWhilePaused_forcesPlaybackToStart() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        core.load([track("a"), track("b"), track("c")])
        core.play()
        core.pause()
        XCTAssertFalse(core.isPlaying)

        core.select(2)

        XCTAssertTrue(core.isPlaying,
                      "Observed: select() starts playback even when previously paused.")
        XCTAssertEqual(core.currentIndex, 2)
    }

    // =========================================================================
    // MARK: - #8 setVolume NaN + volume sync
    // =========================================================================

    /// [FYI] setVolume(NaN) is not sanitized: `min(max(NaN,0),1)` is NaN (all
    /// NaN comparisons are false), so both the observable `volume` and the
    /// engine volume become NaN. A real audio engine receiving NaN volume is at
    /// best undefined. Low severity (callers rarely pass NaN) but unguarded.
    func test_gap_setVolumeNaN_shouldBeSanitized() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)

        core.setVolume(.nan)

        XCTAssertFalse(core.volume.isNaN,
                       "[FYI] setVolume(NaN) leaves observable volume == NaN (clamp does not catch NaN).")
        XCTAssertFalse(engine.volume.isNaN,
                       "[FYI] setVolume(NaN) forwards NaN to the engine.")
    }

    /// Pin: the observable `volume` is initialized from the engine at init time.
    func test_pin_volumeInitializedFromEngine() {
        let engine = FakePlaybackEngine()
        engine.volume = 0.3
        let core = makeCore(engine: engine)
        XCTAssertEqual(core.volume, 0.3)
    }

    /// [FYI] PlayerCore does NOT re-apply its observable `volume` to the engine
    /// on load/next. If something resets the engine's volume out-of-band, the
    /// core's `volume` and `engine.volume` can silently diverge across a track
    /// change. Documents the absence of volume re-sync on transport.
    func test_gap_volumeReappliedToEngineOnTrackChange() {
        let engine = FakePlaybackEngine()
        let core = makeCore(engine: engine)
        let tracks = [track("a"), track("b")]
        core.load(tracks)
        core.setVolume(0.5)
        core.play()

        // Simulate the engine's volume being reset out-of-band (e.g. a fresh
        // engine resource per file in a real implementation).
        engine.volume = 1.0

        core.next() // load + play track b

        XCTAssertEqual(engine.volume, 0.5, accuracy: 0.0001,
                       "[FYI] core does not re-apply its volume to the engine on track change; engine.volume can diverge from core.volume (\(core.volume)).")
    }

    // =========================================================================
    // MARK: - #9 currentIndex / currentTrack consistency after transitions
    // =========================================================================

    /// Pin: after skipping an unplayable track, `currentIndex` and `currentTrack`
    /// both point at the track that actually started (no stale index).
    func test_pin_currentIndexConsistentAfterUnplayableSkip() {
        let engine = FakePlaybackEngine()
        let tracks = [track("bad"), track("good")]
        engine.unloadableURLs = [tracks[0].url]
        let core = makeCore(engine: engine)
        core.load(tracks)

        core.play()

        XCTAssertEqual(core.currentIndex, 1)
        XCTAssertEqual(core.currentTrack, tracks[1],
                       "currentTrack must reflect the track that actually started after a skip.")
    }

    /// Pin: after an all-unplayable stop, the selection is NOT cleared — it
    /// remains at the index the user asked for even though nothing plays. Pinned
    /// so the team confirms "stop but keep selection" is intended.
    func test_pin_allUnplayableStop_keepsSelectionDoesNotClear() {
        let engine = FakePlaybackEngine()
        let tracks = [track("bad1"), track("bad2")]
        engine.unloadableURLs = [tracks[0].url, tracks[1].url]
        let core = makeCore(engine: engine)
        core.load(tracks)

        core.play()

        XCTAssertFalse(core.isPlaying)
        XCTAssertNotNil(core.currentIndex,
                        "Observed: selection is preserved after an all-unplayable stop (not cleared).")
    }

    /// Pin: the unplayable-skip on `next` does NOT wrap under `.off`. If the only
    /// playable track is before the cursor, `.off` stops rather than wrapping
    /// back to it. Pins the documented "no wrap past end with .off" choice on the
    /// skip path specifically.
    func test_pin_unplayableSkipDoesNotWrapUnderRepeatOff() {
        let engine = FakePlaybackEngine()
        let tracks = [track("good"), track("bad")]
        engine.unloadableURLs = [tracks[1].url]
        let core = makeCore(engine: engine)
        core.load(tracks)
        core.repeatMode = .off
        core.select(0) // good plays
        XCTAssertTrue(core.isPlaying)

        core.next() // -> index 1 (bad), unplayable, no wrap under .off -> stop

        XCTAssertFalse(core.isPlaying,
                       "Observed: .off does not wrap back to the earlier playable track on a skip; it stops.")
        XCTAssertGreaterThanOrEqual(engine.stopCount, 1)
    }
}
