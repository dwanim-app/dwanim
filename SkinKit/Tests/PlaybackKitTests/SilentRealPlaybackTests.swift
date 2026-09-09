import AVFoundation
import Foundation
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - SilentRealPlaybackTests

/// Pins the contract of `SilentRealPlayback` itself: the real-playback suite is
/// only silent for as long as the mute actually survives the code path those
/// tests walk. A load, a format-change re-wire or a `PlayerCore` track change
/// that quietly restored the default volume would turn the daily 07:00 CI job
/// back into an alarm clock — with every other test still green, because none of
/// them looks at the volume.
@MainActor
final class SilentRealPlaybackTests: XCTestCase {

    private var tempURLs: [URL] = []

    override func tearDown() async throws {
        await MainActor.run {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            tempURLs.removeAll()
        }
    }

    private func synth(sampleRate: Double, channels: Int) throws -> URL {
        let url = try SineWAVFactory.write(
            duration: 2.0,
            sampleRate: sampleRate,
            channels: channels
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

    private func requireOutputDevice() throws {
        try XCTSkipUnless(
            AudioOutputDeviceProbe.hasOutputDevice(),
            "no audio output device on this machine"
        )
    }

    // MARK: - The factory mutes, and the mute is the real output stage

    func testTheSharedPlayerStartsMuted() {
        let player = SilentRealPlayback.makePlayer()
        XCTAssertEqual(
            player.volume, 0, accuracy: 1e-6,
            "the shared real-playback player must start muted"
        )
    }

    // MARK: - The mute survives the path the real-playback tests walk

    /// load -> play -> a format-CHANGE load -> play: the exact sequence the
    /// format-change and engine-probe suites drive. The clock must advance (so
    /// this is real playback, not a dead engine reading 0) and the volume must
    /// still be 0 at every step.
    func testTheMuteSurvivesLoadPlayAndAFormatChangeRewire() throws {
        try requireOutputDevice()
        let mono48 = try synth(sampleRate: 48_000, channels: 1)
        let stereo44 = try synth(sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        try player.load(mono48)
        XCTAssertEqual(player.volume, 0, accuracy: 1e-6, "a load must not unmute")
        player.play()
        XCTAssertTrue(advances(player, past: 0.05), "the muted player must really render")
        XCTAssertEqual(player.volume, 0, accuracy: 1e-6, "play must not unmute")

        try player.load(stereo44) // the format-change re-wire
        XCTAssertEqual(player.volume, 0, accuracy: 1e-6, "the re-wire must not unmute")
        player.play()
        XCTAssertTrue(advances(player, past: 0.05))
        XCTAssertEqual(
            player.volume, 0, accuracy: 1e-6,
            "the post-re-wire play must not unmute"
        )
        player.stop()
    }

    // MARK: - PlayerCore inherits the mute and re-pushes it on every track

    /// `PlayerCore` reads `engine.volume` in its initializer and re-applies that
    /// value to the engine on EVERY load, so a core built on a muted player is
    /// what keeps the whole click-through queue silent. If that inheritance ever
    /// broke, the transport suite would go loud without failing.
    func testPlayerCoreBuiltOnTheSharedPlayerStaysMutedAcrossTrackChanges() throws {
        try requireOutputDevice()
        let mono48 = try synth(sampleRate: 48_000, channels: 1)
        let stereo44 = try synth(sampleRate: 44_100, channels: 2)

        let player = SilentRealPlayback.makePlayer()
        let core = PlayerCore(engine: player)
        XCTAssertEqual(
            core.volume, 0, accuracy: 1e-6,
            "the core must inherit the engine's muted volume"
        )

        core.load([Track(url: mono48), Track(url: stereo44)])
        core.play()
        XCTAssertTrue(advances(player, past: 0.05), "the muted queue must really render")
        XCTAssertEqual(player.volume, 0, accuracy: 1e-6, "track 1 must play muted")

        core.next() // crosses a rate AND channel boundary, so it re-wires
        XCTAssertTrue(advances(player, past: 0.05))
        XCTAssertEqual(
            player.volume, 0, accuracy: 1e-6,
            "the core's per-load volume re-push must keep track 2 muted too"
        )
        core.pause()
    }
}
