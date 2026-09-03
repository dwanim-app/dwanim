import AVFoundation
import Foundation
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - AVAudioEnginePlayerFormatChangeTests

/// Regression tests for the track-format-change crash (kAudioUnitErr_
/// FormatNotSupported, -10868).
///
/// Before the fix, `load(_:)` re-wired `playerNode -> eq -> mainMixerNode`
/// WHILE THE ENGINE WAS RUNNING. When the new track's `processingFormat`
/// differed from the wired one (48 kHz mono -> 44.1 kHz stereo, the shipped
/// symptom: a real MP3 dropped into a queue of mono m4a files), AVFoundation
/// threw an uncatchable ObjC exception from
/// `AVAudioEngineGraph::UpdateGraphAfterReconfig` — in the app the event loop
/// swallowed it, leaving a half-wired graph: "playing" with a frozen 0:00
/// clock and silence.
///
/// These tests drive REAL playback through format changes, so (like
/// `testPauseFreezesAtPlayedPositionNotZero`) they skip gracefully on a
/// machine with no audio output device: the run-loop poll that proves the
/// render clock advanced doubles as the device guard.
@MainActor
final class AVAudioEnginePlayerFormatChangeTests: XCTestCase {

    private var tempURLs: [URL] = []

    // XCTest's teardown overrides stay nonisolated even in a `@MainActor`
    // class (same note as `AVAudioEnginePlayerTests`), so the async variant
    // hops onto the main actor to drain the temp files.
    override func tearDown() async throws {
        await MainActor.run {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            tempURLs.removeAll()
        }
    }

    // MARK: - Fixtures & helpers

    /// Generates a short sine WAV with the given format — the multi-format
    /// fixtures are built in-test so nothing external (or copyrighted) is
    /// needed to reproduce a 48k/1ch vs 44.1k/2ch format change.
    private func synth(
        duration: Double,
        sampleRate: Double,
        channels: Int,
        frequency: Double = 440
    ) throws -> URL {
        let url = try SineWAVFactory.write(
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            frequency: frequency
        )
        tempURLs.append(url)
        return url
    }

    /// Spins the main run loop until the player's render clock passes
    /// `threshold` seconds (or the deadline expires). Returns whether it did.
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

    /// Device guard: real playback must have advanced the clock. A frozen
    /// clock is only a legitimate SKIP when the independent device probe
    /// (`AudioOutputDeviceProbe`) confirms the machine truly has no output
    /// route; with a device present it is a hard FAILURE — a frozen clock is
    /// exactly the silent-non-playback symptom this fix guards, so skipping on
    /// it would mask the regression (see the probe's doc comment for the
    /// mutation that proved it).
    private func requireRealPlayback(
        _ player: AVAudioEnginePlayer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard !advances(player, past: 0.05) else { return }
        try XCTSkipUnless(
            AudioOutputDeviceProbe.hasOutputDevice(),
            "no audio output device on this machine; "
                + "the format-change scenarios need real playback",
            file: file,
            line: line
        )
        XCTFail(
            "an output device exists but the render clock did not advance — "
                + "the engine is not actually playing",
            file: file,
            line: line
        )
        // Halt the scenario: its downstream asserts/waits would only pile
        // timeout noise on top of the recorded failure.
        throw FrozenClockWithDeviceError()
    }

    /// Thrown (after the failure is recorded) to abort a scenario whose render
    /// clock froze even though an output device exists.
    private struct FrozenClockWithDeviceError: Error {}

    // MARK: - The crash scenario (48k mono -> 44.1k stereo)

    /// The shipped bug: play a 48 kHz mono track, then load and play a
    /// 44.1 kHz STEREO track. Before the fix this crashed the process with
    /// -10868 inside `load` (see the class note). After it: the second track
    /// really plays — engine running, `isPlaying` true, clock advancing — and
    /// its natural finish still fires (the generation gating survives the
    /// re-wire), so auto-advance keeps working across a format change.
    func testLoadDifferentFormatThenPlayAdvancesAndFinishes() throws {
        let monoA = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)
        let stereoB = try synth(duration: 0.4, sampleRate: 44_100, channels: 2)

        let player = AVAudioEnginePlayer()
        try player.load(monoA)
        player.play()
        try requireRealPlayback(player)

        // The format change (48k/1ch -> 44.1k/2ch). Pre-fix: process death.
        try player.load(stereoB)

        let finished = expectation(description: "natural finish after a format change")
        finished.assertForOverFulfill = true
        player.onPlaybackFinished = { finished.fulfill() }

        player.play()
        XCTAssertTrue(
            player.isPlaying,
            "after a format-change load + play the engine must actually be running"
        )
        XCTAssertTrue(
            advances(player, past: 0.05),
            "the clock must advance past 0:00 on the new-format track (the bug froze it)"
        )

        // The 0.4 s track must drain to its natural finish.
        wait(for: [finished], timeout: 5.0)
        player.stop()
    }

    /// Round trip: after switching 48k/1ch -> 44.1k/2ch, switching BACK to the
    /// original format must also play (the re-wire tracks the format both ways).
    func testFormatChangeBackToOriginalFormatStillPlays() throws {
        let monoA = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)
        let stereoB = try synth(duration: 0.5, sampleRate: 44_100, channels: 2)
        let monoC = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)

        let player = AVAudioEnginePlayer()
        try player.load(monoA)
        player.play()
        try requireRealPlayback(player)

        try player.load(stereoB)
        player.play()
        XCTAssertTrue(
            advances(player, past: 0.05),
            "44.1k/2ch after 48k/1ch must advance"
        )

        try player.load(monoC)
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(
            advances(player, past: 0.05),
            "switching back to 48k/1ch must advance too"
        )
        player.stop()
    }

    /// A channel-count-ONLY change (48k mono -> 48k STEREO, same rate) is a
    /// format change too and used to hit the same -10868 re-wire crash. The
    /// engine-stopped assert right after the load pins that the REWIRE PATH was
    /// actually taken (mirroring `testSameFormatReloadDoesNotStopTheEngine`):
    /// "it plays" alone cannot see it, because a stereo file scheduled into a
    /// still-mono-wired graph plays too — a rate-only format comparison would
    /// ship green while rendering stereo tracks through a mono-wired chain.
    func testChannelCountOnlyChangePlays() throws {
        let mono = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)
        let stereo = try synth(duration: 0.5, sampleRate: 48_000, channels: 2)

        let player = AVAudioEnginePlayer()
        try player.load(mono)
        player.play()
        try requireRealPlayback(player)

        try player.load(stereo)
        XCTAssertFalse(
            player.isEngineRunningForTesting,
            "a channel-count-only change IS a format change: the load must stop "
                + "the engine and re-wire; comparing sample rate alone would skip "
                + "the re-wire and leave the stereo track playing through a "
                + "mono-wired graph"
        )
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(
            advances(player, past: 0.05),
            "a channel-count-only format change must still play"
        )
        player.stop()
    }

    // MARK: - Same-format loads must stay gapless

    /// Loading a SAME-format track must not stop the engine: consecutive
    /// same-format tracks are the app's normal gapless path, and the fix must
    /// only pay the stop/re-wire cost when the format actually changed.
    /// Asserted via the test-only `isEngineRunningForTesting` read (the public
    /// `isPlaying` cannot see this — `load` always stops the player node).
    func testSameFormatReloadDoesNotStopTheEngine() throws {
        let first = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)
        let second = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)

        let player = AVAudioEnginePlayer()
        try player.load(first)
        player.play()
        try requireRealPlayback(player)
        XCTAssertTrue(player.isEngineRunningForTesting)

        try player.load(second)
        XCTAssertTrue(
            player.isEngineRunningForTesting,
            "a same-format load must leave the running engine untouched (no added gap)"
        )

        player.play()
        XCTAssertTrue(
            advances(player, past: 0.05),
            "the same-format follow-up track must play normally"
        )
        player.stop()
    }

    // MARK: - Load while paused

    /// pause -> load(other format) -> play is the other legal call order (the
    /// app normally does load-then-play back to back): the re-wire must work
    /// from the paused state and `play()`'s `startEngineIfNeeded()` must bring
    /// the stopped engine back.
    func testLoadDifferentFormatWhilePausedThenPlayAdvances() throws {
        let monoA = try synth(duration: 2.0, sampleRate: 48_000, channels: 1)
        let stereoB = try synth(duration: 0.5, sampleRate: 44_100, channels: 2)

        let player = AVAudioEnginePlayer()
        try player.load(monoA)
        player.play()
        try requireRealPlayback(player)
        player.pause()

        try player.load(stereoB)
        player.play()
        XCTAssertTrue(
            player.isPlaying,
            "play after a paused format-change load must actually run"
        )
        XCTAssertTrue(
            advances(player, past: 0.05),
            "the clock must advance after pause -> load(new format) -> play"
        )
        player.stop()
    }

    // MARK: - EQ still applies across a format change

    /// The graph-order pin (`playerNode -> eq -> mainMixerNode`, tap on the
    /// mixer input = post-EQ) must survive the format-change re-wire: if the
    /// re-wire dropped or bypassed the EQ node, a +12 dB band boost would stop
    /// changing the rendered audio. Proven with the live production tap (the
    /// DSP-proof technique, live instead of offline): the SAME post-change
    /// 1 kHz tone is captured once flat and once with the 1 kHz band boosted,
    /// and the boosted capture must carry clearly more energy.
    func testEqualizerStillAppliesAfterFormatChange() throws {
        let flatState = EQState(
            enabled: true,
            preamp: 0,
            bands: [Double](repeating: 0, count: EQState.bandCount)
        )
        var boostBands = [Double](repeating: 0, count: EQState.bandCount)
        boostBands[4] = 12 // band 4 = 1 kHz, matching the 1 kHz test tone
        let boostState = EQState(enabled: true, preamp: 0, bands: boostBands)

        let flatRMS = try postFormatChangeToneRMS(applying: flatState)
        let boostRMS = try postFormatChangeToneRMS(applying: boostState)

        XCTAssertGreaterThan(flatRMS, 0, "flat capture must contain signal")
        XCTAssertGreaterThan(boostRMS, 0, "boosted capture must contain signal")

        // +12 dB on the tone's own band is a ~4x amplitude rise; demand a
        // clearly measurable >6 dB so finite band Q and capture jitter cannot
        // flake the assertion.
        let gainDB = 20 * log10(boostRMS / flatRMS)
        XCTAssertGreaterThan(
            gainDB,
            6,
            "a +12 dB 1 kHz band boost must measurably lift the 1 kHz tone after "
                + "a format change (measured \(String(format: "%.1f", gainDB)) dB); "
                + "no lift means the re-wire dropped the EQ from the graph"
        )
    }

    /// Plays a 1 kHz 44.1k/2ch tone AFTER a 48k/1ch -> 44.1k/2ch format change
    /// with `state` applied (re-pushed after the load, exactly as
    /// `PlayerCore.playCurrent` does), capturing ~0.3 s through the production
    /// tap; returns the RMS of the captured signal (near-zero silence excluded).
    private func postFormatChangeToneRMS(applying state: EQState) throws -> Double {
        let mono48 = try synth(duration: 0.3, sampleRate: 48_000, channels: 1)
        let tone = try synth(
            duration: 1.5,
            sampleRate: 44_100,
            channels: 2,
            frequency: 1_000
        )

        let player = AVAudioEnginePlayer()
        try player.load(mono48)
        player.applyEqualizer(state)

        try player.load(tone) // the format change under test
        player.applyEqualizer(state) // PlayerCore re-pushes EQ on every load

        let collector = LockedSampleCollector()
        player.installTap { mono, _ in collector.append(mono) }
        player.play()
        let advanced = advances(player, past: 0.35, within: 3.0)
        player.stop()
        player.removeTap()

        if !advanced {
            // Same skip-mask guard as `requireRealPlayback`: only a truly
            // deviceless machine may skip; a frozen clock WITH a device is the
            // regression itself.
            try XCTSkipUnless(
                AudioOutputDeviceProbe.hasOutputDevice(),
                "no audio output device on this machine"
            )
            XCTFail(
                "an output device exists but the post-format-change tone did "
                    + "not advance the render clock"
            )
            throw FrozenClockWithDeviceError()
        }
        let rms = collector.rms(ignoringBelow: 1e-3)
        try XCTSkipUnless(
            collector.count > 4_096,
            "tap delivered too few samples to measure"
        )
        return rms
    }

    // MARK: - Real-file guard (the exact shipped scenario)

    /// The literal reported crash: a real 44.1 kHz stereo MP3 loaded after a
    /// 48 kHz mono track. The synthesized 44.1k/2ch fixtures above are the
    /// always-on guard; this one additionally runs the true decoder path when
    /// the reporter's file is present (skipped elsewhere).
    func testRealMP3AfterMonoM4APlays() throws {
        let mp3 = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .appendingPathComponent(
                "Danzon De Pasion (Sting) - Jimmy Fontanez_Media Right Productions.mp3"
            )
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: mp3.path),
            "reporter's 44.1k stereo MP3 not present on this machine"
        )

        let mono48 = try synth(duration: 0.5, sampleRate: 48_000, channels: 1)
        let player = AVAudioEnginePlayer()
        try player.load(mono48)
        player.play()
        try requireRealPlayback(player)

        try player.load(mp3)
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(
            advances(player, past: 0.05),
            "the real 44.1k stereo MP3 must play after a 48k mono track"
        )
        player.stop()
    }
}

// MARK: - LockedSampleCollector

/// Thread-safe sink for the LIVE tap (unlike the offline DSP-proof's
/// collector, the live tap appends on the audio render thread while the test
/// reads on main, so every access is lock-guarded).
private final class LockedSampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ mono: [Float]) {
        lock.lock()
        samples.append(contentsOf: mono)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    /// RMS of the captured signal, excluding samples whose magnitude is below
    /// `floor` (leading spin-up / trailing stop silence would otherwise dilute
    /// the two captures by different, timing-dependent amounts).
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
