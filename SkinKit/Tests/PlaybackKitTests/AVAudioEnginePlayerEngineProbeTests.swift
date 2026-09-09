import AVFoundation
import Foundation
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - AVAudioEnginePlayerEngineProbeTests

/// Adversarial probes for the format-change re-wire, born from a fresh-context
/// mutation pass on `AVAudioEnginePlayerFormatChangeTests`: that suite's
/// clock-based skip guard let two engine-lifecycle mutants ship green (every
/// runtime assert sat downstream of "skip unless the clock advanced", and a
/// dead engine freezes the clock — see `AudioOutputDeviceProbe`).
///
/// These tests use the INDEPENDENT device probe as their only skip, so on a
/// device-equipped machine they FAIL (never skip) when the fix mishandles a
/// sequence. They cover call orders the author's suite does not: rapid
/// alternating loads, seek/stop/pause interleavings, stale completions,
/// mixer-state and tap survival — plus the direct engine-running assert that
/// killed both surviving mutants.
@MainActor
final class AVAudioEnginePlayerEngineProbeTests: XCTestCase {

    private var tempURLs: [URL] = []

    // Same nonisolated-teardown note as `AVAudioEnginePlayerTests`.
    override func tearDown() async throws {
        await MainActor.run {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            tempURLs.removeAll()
        }
    }

    // MARK: - Fixtures & helpers

    /// - Parameter amplitude: peak amplitude of the tone. Pass `0` (digital
    ///   silence) for a scenario that cannot use the shared muted player because
    ///   the VOLUME ITSELF is the subject under test; every other scenario keeps
    ///   the default signal and is silenced at the output instead
    ///   (`SilentRealPlayback`).
    private func synth(
        duration: Double,
        sampleRate: Double,
        channels: Int,
        frequency: Double = 440,
        amplitude: Double = 0.5
    ) throws -> URL {
        let url = try SineWAVFactory.write(
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            frequency: frequency,
            amplitude: amplitude
        )
        tempURLs.append(url)
        return url
    }

    @discardableResult
    private func advances(
        _ player: AVAudioEnginePlayer,
        past threshold: TimeInterval,
        within seconds: TimeInterval = 2.0
    ) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while player.currentTime < threshold, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return player.currentTime >= threshold
    }

    /// The one legitimate skip: a machine with no output route at all. Unlike
    /// the player's own clock, this throwaway-engine probe cannot be frozen by
    /// a player regression, so it never masks one.
    private func requireOutputDevice() throws {
        try XCTSkipUnless(
            AudioOutputDeviceProbe.hasOutputDevice(),
            "no audio output device on this machine"
        )
    }

    // MARK: - Engine actually running after a format-change play (skip-mask guard)

    /// Direct engine-state assert that CANNOT be skip-masked: after a
    /// format-change load + play on a device-equipped machine, the engine must
    /// be running. This single test kills both suite-surviving mutants —
    /// "`play()` never restarts the engine" and "re-wire remakes only the
    /// playerNode -> eq hop" (whose swallowed `engine.start()` failure also
    /// leaves `isRunning` false).
    func testEngineIsRunningAfterFormatChangePlay() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        try player.load(mono)
        player.play()
        XCTAssertTrue(player.isEngineRunningForTesting, "engine must run on first play")
        try player.load(stereo)
        player.play()
        XCTAssertTrue(
            player.isEngineRunningForTesting,
            "engine must be restarted after a format-change load + play"
        )
        XCTAssertTrue(advances(player, past: 0.05))
        player.stop()
    }

    // MARK: - Rapid A -> B -> A -> B (4 loads back to back)

    func testRapidAlternatingFormatLoads() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        for _ in 0..<2 {
            try player.load(mono)
            player.play()
            try player.load(stereo)
            player.play()
        }
        XCTAssertTrue(player.isPlaying, "after rapid A/B/A/B the engine must be running")
        XCTAssertTrue(
            advances(player, past: 0.05),
            "rapid alternating-format loads must leave a live, advancing player"
        )
        player.stop()
    }

    // MARK: - Format change immediately after a seek

    func testFormatChangeImmediatelyAfterSeek() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        try player.load(mono)
        player.play()
        player.seek(to: 3.0)
        try player.load(stereo) // format change with a live post-seek segment
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(advances(player, past: 0.05), "must advance from 0 on the new track")
        XCTAssertLessThan(
            player.currentTime, 2.0,
            "the old track's 3.0s seek base must not leak into the new track"
        )
        player.stop()
    }

    // MARK: - stop() -> load(other format) -> play

    func testStopThenFormatChangeLoadThenPlay() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        try player.load(mono)
        player.play()
        XCTAssertTrue(advances(player, past: 0.05))
        player.stop()
        try player.load(stereo)
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(advances(player, past: 0.05), "stop -> format-change load -> play must run")
        player.stop()
    }

    // MARK: - Stale completion across a format-change load

    /// The previous track's segment completion (fired by the node stop inside
    /// `resetPositionState`) must NOT count as a natural finish of the NEW
    /// track — that would auto-advance and skip a track.
    func testNoStaleFinishAfterFormatChangeLoad() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        var finishes = 0
        player.onPlaybackFinished = { finishes += 1 }

        try player.load(mono)
        player.play()
        XCTAssertTrue(advances(player, past: 0.05))
        try player.load(stereo) // stops node mid-segment -> old completion fires
        player.play()
        // Drain the main queue generously: any stale finish would land here.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(
            finishes, 0,
            "the old track's stopped-segment completion must not fire onPlaybackFinished"
        )
        player.stop()
    }

    // MARK: - Volume and pan survive the re-wire

    /// The ONE scenario that cannot be silenced with `SilentRealPlayback`: its
    /// subject IS the volume, and a probe value of 0 would stop it catching the
    /// plausible regression "the re-wire mutes the graph and never restores it".
    /// So the probe stays at 0.37 and the SOURCE is silenced instead — the sine
    /// files are written at amplitude 0, which changes nothing these assertions
    /// look at (the render clock counts frames, not loudness) while keeping the
    /// daily CI run quiet.
    func testVolumeAndPanSurviveFormatChange() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1, amplitude: 0)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2, amplitude: 0)

        let player = AVAudioEnginePlayer()
        try player.load(mono)
        player.volume = 0.37
        player.pan = -0.5
        player.play()
        XCTAssertTrue(advances(player, past: 0.05))

        try player.load(stereo)
        XCTAssertEqual(player.volume, 0.37, accuracy: 0.001, "volume lost across the re-wire")
        XCTAssertEqual(player.pan, -0.5, accuracy: 0.001, "pan lost across the re-wire")
        player.play()
        XCTAssertTrue(advances(player, past: 0.05))
        XCTAssertEqual(player.volume, 0.37, accuracy: 0.001)
        XCTAssertEqual(player.pan, -0.5, accuracy: 0.001)
        player.stop()
    }

    // MARK: - A tap installed BEFORE the format change still delivers audio

    /// The format-change EQ test installs its tap AFTER the change; the app
    /// (visualizer) installs it ONCE at startup. If the re-wire silenced or
    /// broke a pre-installed tap, the spectrum would die on the first format
    /// change.
    ///
    /// One of the two tests in the target that MEASURE the tap, so it cannot use
    /// the muted player: the tap sits after the volume fader, and at volume 0 it
    /// delivers its full 14 400 samples as zeros. It runs attenuated instead —
    /// see `SilentRealPlayback.tapMeasuringVolume`, whose doc carries the
    /// measurement.
    func testPreInstalledTapStillDeliversAfterFormatChange() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(
            duration: 5.0, sampleRate: 44_100, channels: 2, frequency: 1_000
        )

        let player = SilentRealPlayback.makeTapMeasuringPlayer()
        let collector = LockedProbeCollector()
        player.installTap { mono, _ in collector.append(mono) }

        try player.load(mono)
        player.play()
        XCTAssertTrue(advances(player, past: 0.1))

        try player.load(stereo) // format change with the tap still installed
        collector.reset()
        player.play()
        let advanced = advances(player, past: 0.35, within: 3.0)
        player.stop()
        player.removeTap()
        XCTAssertTrue(advanced, "post-change track must play")
        XCTAssertGreaterThan(
            collector.rms(ignoringBelow: 1e-3), 0,
            "a tap installed before the format change must still deliver post-change audio"
        )
        XCTAssertGreaterThan(collector.count, 4_096, "tap delivered too few samples")
    }

    // MARK: - Paused mid-file, format change: the old pause state must not leak

    func testPausedTimeDoesNotLeakIntoNewFormatTrack() throws {
        try requireOutputDevice()
        let mono = try synth(duration: 5.0, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 5.0, sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        try player.load(mono)
        player.play()
        XCTAssertTrue(advances(player, past: 0.2))
        player.pause()
        let frozen = player.currentTime
        XCTAssertGreaterThan(frozen, 0.15)

        try player.load(stereo)
        XCTAssertEqual(
            player.currentTime, 0, accuracy: 0.001,
            "a fresh load must report 0:00, not the old track's paused position"
        )
        player.play()
        XCTAssertTrue(advances(player, past: 0.05))
        player.stop()
    }
}

// MARK: - LockedProbeCollector

/// Thread-safe sink for the live tap (appends on the audio render thread while
/// the test reads on main, so every access is lock-guarded).
private final class LockedProbeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ mono: [Float]) {
        lock.lock()
        samples.append(contentsOf: mono)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    func rms(ignoringBelow floor: Float) -> Double {
        lock.lock()
        defer { lock.unlock() }
        var sum = 0.0
        var counted = 0
        for sample in samples where abs(sample) >= floor {
            sum += Double(sample) * Double(sample)
            counted += 1
        }
        guard counted > 0 else { return 0 }
        return (sum / Double(counted)).squareRoot()
    }
}
