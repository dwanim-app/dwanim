import AVFoundation
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - AVAudioEnginePlayerTests

/// Headless tests for the concrete engine. Real-time audible playback needs an
/// output device and is therefore NOT exercised here (see the offline-render
/// test for the decode+graph proof). These tests drive the load/seek/clamp
/// logic and the duration reporting, all of which are deterministic.
final class AVAudioEnginePlayerTests: XCTestCase {

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
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

    /// An uncompressed 44.1k/16-bit/stereo WAV reports its large effective
    /// bitrate (~1411 kbps): the estimated data rate is positive and in the right
    /// ballpark. (The render side clips this to the field width; here we only
    /// prove the engine surfaces a sensible positive value.)
    func testBitrateReportsPositiveDataRateForUncompressedStereo() throws {
        let url = try synthWAV(duration: 1.0, sampleRate: 44_100, channels: 2)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        // 44100 * 16 * 2 = 1_411_200 bits/s -> ~1411 kbps. Allow generous slack
        // for header/estimate variation, but require it to be clearly positive
        // and uncompressed-scale (well above any lossy rate).
        XCTAssertGreaterThan(player.bitrateKbps, 1000)
        XCTAssertLessThan(player.bitrateKbps, 2000)
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

    // MARK: - Stop does not fire finished

    func testStopDoesNotInvokePlaybackFinished() throws {
        let url = try synthWAV(duration: 1.0)
        let player = AVAudioEnginePlayer()
        try player.load(url)

        var finishedCount = 0
        player.onPlaybackFinished = { finishedCount += 1 }

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

        var finishedCount = 0
        player.onPlaybackFinished = { finishedCount += 1 }

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
