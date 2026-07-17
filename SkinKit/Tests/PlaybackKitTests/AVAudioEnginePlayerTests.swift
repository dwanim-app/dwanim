import AVFoundation
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - AVAudioEnginePlayerTests

/// Headless tests for the concrete engine. Real-time audible playback needs an
/// output device and is therefore NOT exercised here (see the offline-render
/// test for the decode+graph proof). These tests drive the load/seek/clamp
/// logic and the duration reporting, all of which are deterministic.
// `@MainActor`: the engine's `onPlaybackFinished` handler is now `@MainActor`
// (it drives the `@MainActor` `PlayerCore` in production), so the tests that
// install one and assert on its effect run on the main actor too — letting the
// handler mutate the `@MainActor`-isolated `finishedCount` below.
@MainActor
final class AVAudioEnginePlayerTests: XCTestCase {

    // Temp-file bookkeeping: appended in `synthWAV` (main actor, like every
    // test method here) and drained in `tearDown()`. XCTest declares its
    // teardown overrides nonisolated — an override in a `@MainActor` class does
    // NOT become isolated — so the drain uses the async `tearDown()` and hops
    // onto the main actor explicitly (see below); the property itself needs no
    // isolation exemption.
    private var tempURLs: [URL] = []

    /// Count of natural-finish callbacks for the stop/seek "must not finish" tests.
    /// A main-actor-isolated property (not a captured local `var`) so the
    /// `@Sendable @MainActor` `onPlaybackFinished` closure can mutate it without a
    /// data-race diagnostic. Reset at the start of each test that uses it.
    private var finishedCount = 0

    // XCTest's teardown overrides stay nonisolated even in a `@MainActor` class,
    // so the synchronous `tearDownWithError()` cannot touch the main-isolated
    // `tempURLs` without a strict-concurrency diagnostic. The async variant can
    // hop actors properly: `MainActor.run` puts the drain on the main actor.
    override func tearDown() async throws {
        await MainActor.run {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            tempURLs.removeAll()
        }
    }

    private func synthWAV(
        duration: Double = 1.0,
        sampleRate: Double = 44_100,
        channels: Int = 1
    ) throws -> URL {
        let url = try SineWAVFactory.write(
            duration: duration,
            sampleRate: sampleRate,
            channels: channels
        )
        tempURLs.append(url)
        return url
    }

    // MARK: - Loading & duration

    func testLoadReportsDurationAboutOneSecond() throws {
        let url = try synthWAV(duration: 1.0, sampleRate: 44_100)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        // Within one frame of 1.0s.
        XCTAssertEqual(player.duration, 1.0, accuracy: 1.0 / 44_100)
    }

    func testLoadStereoReportsDuration() throws {
        let url = try synthWAV(duration: 0.5, sampleRate: 44_100, channels: 2)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        XCTAssertEqual(player.duration, 0.5, accuracy: 1.0 / 44_100)
    }

    func testLoadInvalidFileThrows() {
        let bogus = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).wav")
        let player = AVAudioEnginePlayer()
        XCTAssertThrowsError(try player.load(bogus))
    }

    func testDurationIsZeroBeforeLoad() {
        let player = AVAudioEnginePlayer()
        XCTAssertEqual(player.duration, 0)
    }

    // MARK: - TrackFormatProviding (kbps / kHz facts)

    /// Before any load, both format facts are 0 (the kbps/kHz boxes read blank).
    func testFormatFactsAreZeroBeforeLoad() {
        let provider: TrackFormatProviding = AVAudioEnginePlayer()
        XCTAssertEqual(provider.sampleRateHz, 0)
        XCTAssertEqual(provider.bitrateKbps, 0)
    }

    /// After loading a 44.1 kHz file, `sampleRateHz` reports the processing
    /// format's sample rate (so the kHz box shows round(44100/1000) = 44).
    func testSampleRateReportsLoadedFileRate() throws {
        let url = try synthWAV(duration: 1.0, sampleRate: 44_100)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        XCTAssertEqual(player.sampleRateHz, 44_100, accuracy: 1)
    }

    /// A 22.05 kHz file reports its own rate, proving the value tracks the file
    /// (kHz box -> round(22050/1000) = 22).
    func testSampleRateTracksDifferentFileRate() throws {
        let url = try synthWAV(duration: 0.5, sampleRate: 22_050)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        XCTAssertEqual(player.sampleRateHz, 22_050, accuracy: 1)
    }

    /// Bitrate is deferred to M5 (it needs the async
    /// `AVAsset.load(.estimatedDataRate)` API), so after any load `bitrateKbps`
    /// stays 0 and the kbps box reads blank. The sync sampleRate facts above are
    /// unaffected.
    func testBitrateIsZeroPendingAsyncAssetLoading() throws {
        let url = try synthWAV(duration: 1.0, sampleRate: 44_100, channels: 2)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        XCTAssertEqual(player.bitrateKbps, 0)
    }

    // MARK: - Initial state

    func testInitialStateIsStoppedAtZero() throws {
        let url = try synthWAV()
        let player = AVAudioEnginePlayer()
        try player.load(url)

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0, accuracy: 1e-6)
    }

    // MARK: - Seek clamping (observed via currentTime / position base)

    func testSeekNegativeClampsToZero() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        player.seek(to: -10)
        // Not playing, so currentTime reflects the seek base only.
        XCTAssertEqual(player.currentTime, 0, accuracy: 1e-6)
    }

    func testSeekBeyondDurationClampsToDuration() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        player.seek(to: 999)
        XCTAssertEqual(player.currentTime, player.duration, accuracy: 1e-3)
    }

    func testSeekMidFileSetsPositionBase() throws {
        let url = try synthWAV(duration: 2.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        player.seek(to: 1.0)
        // Idle: currentTime equals the seek base since no render time elapsed.
        XCTAssertEqual(player.currentTime, 1.0, accuracy: 1e-2)
    }

    func testSeekOnEmptyEngineIsNoOp() {
        let player = AVAudioEnginePlayer()
        player.seek(to: 5) // nothing loaded
        XCTAssertEqual(player.currentTime, 0)
    }

    // MARK: - currentTime invariants (spin-up transient, Bug 1)

    /// Right after `play()` the render clock may be spinning up: `playerTime`
    /// can be `nil`, the node time may not be sample-time-valid, or `sampleTime`
    /// can be stale/negative. In every one of those states `currentTime` must
    /// hold at the (non-negative) base and never read back below zero — a stale
    /// or negative sample time must never subtract. This is deterministic and
    /// needs no output device: whatever the transient, the value stays `>= 0`.
    func testCurrentTimeNeverNegativeDuringPlayTransient() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        player.play()
        for _ in 0..<200 {
            XCTAssertGreaterThanOrEqual(
                player.currentTime,
                0,
                "currentTime must never blip below zero during spin-up"
            )
        }
        player.stop()
    }

    // MARK: - Pause position freeze

    /// Reported bug: pressing pause made the time display show 00:00 instead of
    /// freezing where playback was. `AVAudioPlayerNode.playerTime(forNodeTime:)`
    /// returns nil while the node is paused, so `currentTime` fell back to the
    /// seek base (0 for a from-the-start track). The fix caches the live position
    /// at `pause()`. This needs REAL playback to advance the clock, so it skips
    /// gracefully when there is no audio output device (e.g. headless CI).
    func testPauseFreezesAtPlayedPositionNotZero() throws {
        let url = try synthWAV(duration: 5.0, sampleRate: 44_100)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        player.play()
        // Spin the run loop until real playback crosses a small threshold.
        let deadline = Date().addingTimeInterval(2.0)
        while player.currentTime < 0.05, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let played = player.currentTime
        try XCTSkipUnless(
            played >= 0.05,
            "engine did not advance the render clock (no audio output device); the pause-freeze path needs real playback"
        )

        player.pause()
        let paused = player.currentTime
        XCTAssertGreaterThan(
            paused, 0.0,
            "paused time collapsed to 0 — the reported bug"
        )
        XCTAssertEqual(
            paused, played, accuracy: 0.20,
            "paused time should freeze at (roughly) the play position, not reset"
        )
        player.stop()
    }

    /// Seeking AT/PAST the end WHILE PLAYING must fire `onPlaybackFinished` (the
    /// natural-finish path), not die silently. Before the fix, a seek to ~100%
    /// scheduled nothing (`remaining == 0`), so no completion ever fired: the
    /// display froze at the duration and auto-advance/repeat never ran.
    /// Deterministic — the finish is synthesized, no real audio drain needed.
    func testSeekToEndWhilePlayingFiresPlaybackFinished() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        let finished = expectation(description: "onPlaybackFinished on seek-to-end")
        player.onPlaybackFinished = { finished.fulfill() }

        player.play()
        player.seek(to: player.duration)  // at/past the last frame

        wait(for: [finished], timeout: 2.0)
        XCTAssertFalse(player.isPlaying, "the synthesized finish must stop playback")
        XCTAssertEqual(
            player.currentTime, player.duration, accuracy: 0.01,
            "the position must report the end after the synthesized finish"
        )
    }

    /// A PAUSED seek-to-end must NOT fire the finish (it just parks at the end),
    /// so pausing near the end and scrubbing to 100% does not steal an advance.
    func testSeekToEndWhilePausedDoesNotFireFinished() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        var fired = false
        player.onPlaybackFinished = { fired = true }

        player.pause()
        player.seek(to: player.duration)

        // Drain the main queue so a (wrong) async finish would have run.
        let drain = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)
        XCTAssertFalse(fired, "a paused seek-to-end must not synthesize a finish")
    }

    /// A play() AFTER a paused seek-to-end must fire `onPlaybackFinished`
    /// exactly once (the natural-finish path), not enter a permanent silent
    /// "playing" state. Before the fix, the paused seek parked with the seek
    /// base at the duration and nothing scheduled (`remaining > 0` guard), so
    /// play() started the node over an EMPTY queue: `isPlaying` read true, the
    /// position pinned at the duration, and no completion EVER fired — no
    /// auto-advance/repeat, no recovery without another manual transport press.
    /// Deterministic — the finish is synthesized, no real audio drain needed.
    func testPlayAfterPausedSeekToEndFiresPlaybackFinishedOnce() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        let finished = expectation(description: "onPlaybackFinished on play after paused seek-to-end")
        finished.assertForOverFulfill = true // a double-fire fails the test
        player.onPlaybackFinished = { finished.fulfill() }

        player.pause()
        player.seek(to: player.duration) // parks at the end, nothing scheduled
        player.play()

        wait(for: [finished], timeout: 2.0)
        XCTAssertFalse(
            player.isPlaying,
            "the synthesized finish must not leave a silent 'playing' state"
        )
        XCTAssertEqual(
            player.currentTime, player.duration, accuracy: 0.01,
            "the position must report the end after the synthesized finish"
        )

        // Drain the main queue so a (wrong) SECOND finish would have run —
        // `assertForOverFulfill` above turns any double-fire into a failure.
        let drain = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)
    }

    /// Seeking WHILE paused must clear the paused-position freeze and report the
    /// seek target (not the frozen time). Deterministic — no real playback needed:
    /// a pause from a stopped node caches 0, and the seek must override it.
    func testSeekWhilePausedReportsSeekTargetNotFrozenTime() throws {
        let url = try synthWAV(duration: 5.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        player.pause()  // caches pausedTime = currentTime = 0
        XCTAssertEqual(player.currentTime, 0, accuracy: 1e-6)

        player.seek(to: 2.5)
        XCTAssertEqual(
            player.currentTime, 2.5, accuracy: 0.05,
            "a seek while paused must report the target, not the frozen 0"
        )
        player.stop()
    }

    /// With nothing loaded the engine cannot be running, so `isPlaying` must be
    /// `false` even though `play()` was called — the engine-running guard (Bug
    /// 2) prevents a no-device/empty engine from masquerading as playing.
    func testIsPlayingFalseWhenEngineNotRunning() {
        let player = AVAudioEnginePlayer()
        player.play() // no file loaded, engine never starts rendering
        XCTAssertFalse(
            player.isPlaying,
            "a never-started engine must not report isPlaying == true"
        )
    }

    // MARK: - Volume

    func testVolumeRoundTrips() {
        let player = AVAudioEnginePlayer()
        player.volume = 0.3
        XCTAssertEqual(player.volume, 0.3, accuracy: 1e-6)
    }

    func testVolumeClampsAboveOne() {
        let player = AVAudioEnginePlayer()
        player.volume = 5
        XCTAssertEqual(player.volume, 1.0, accuracy: 1e-6)
    }

    func testVolumeClampsBelowZero() {
        let player = AVAudioEnginePlayer()
        player.volume = -1
        XCTAssertEqual(player.volume, 0.0, accuracy: 1e-6)
    }

    // MARK: - Pan / balance

    func testPanDefaultsToCentered() {
        let player = AVAudioEnginePlayer()
        XCTAssertEqual(player.pan, 0, accuracy: 1e-6)
    }

    func testPanRoundTrips() {
        let player = AVAudioEnginePlayer()
        player.pan = -0.5
        XCTAssertEqual(player.pan, -0.5, accuracy: 1e-6)
        player.pan = 0.75
        XCTAssertEqual(player.pan, 0.75, accuracy: 1e-6)
    }

    func testPanClampsAboveOne() {
        let player = AVAudioEnginePlayer()
        player.pan = 5
        XCTAssertEqual(player.pan, 1.0, accuracy: 1e-6)
    }

    func testPanClampsBelowMinusOne() {
        let player = AVAudioEnginePlayer()
        player.pan = -5
        XCTAssertEqual(player.pan, -1.0, accuracy: 1e-6)
    }

    /// The pan survives a track-change `reconnect` (it lives on the player node,
    /// whose identity is stable), so a loaded file keeps the dialed-in balance.
    func testPanPersistsAcrossLoad() throws {
        let player = AVAudioEnginePlayer()
        player.pan = -0.6
        let url = try synthWAV(duration: 0.5, sampleRate: 44_100, channels: 2)
        try player.load(url)
        XCTAssertEqual(player.pan, -0.6, accuracy: 1e-6)
    }

    // MARK: - TrackFormatProviding (channel count)

    func testChannelCountIsZeroBeforeLoad() {
        let provider: TrackFormatProviding = AVAudioEnginePlayer()
        XCTAssertEqual(provider.channelCount, 0)
    }

    func testChannelCountReportsMono() throws {
        let url = try synthWAV(duration: 0.5, sampleRate: 44_100, channels: 1)
        let player = AVAudioEnginePlayer()
        try player.load(url)
        XCTAssertEqual(player.channelCount, 1)
    }

    func testChannelCountReportsStereo() throws {
        let url = try synthWAV(duration: 0.5, sampleRate: 44_100, channels: 2)
        let player = AVAudioEnginePlayer()
        try player.load(url)
        XCTAssertEqual(player.channelCount, 2)
    }

    // MARK: - Stop does not fire finished

    func testStopDoesNotInvokePlaybackFinished() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        finishedCount = 0
        player.onPlaybackFinished = { [weak self] in self?.finishedCount += 1 }

        player.play()
        player.stop()

        // Pump the main run loop briefly so any (incorrectly) dispatched
        // completion would have a chance to run.
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(
            finishedCount,
            0,
            "stop() must not be reported as a natural finish"
        )
    }

    func testSeekDoesNotInvokePlaybackFinished() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        finishedCount = 0
        player.onPlaybackFinished = { [weak self] in self?.finishedCount += 1 }

        player.play()
        player.seek(to: 0.5)

        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(
            finishedCount,
            0,
            "seek() reschedule must not be reported as a natural finish"
        )
    }
}
