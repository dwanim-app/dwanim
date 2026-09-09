import AVFoundation
@testable import PlaybackKit

// MARK: - SilentRealPlayback

/// The factory every test in this target uses to build the REAL
/// `AVAudioEnginePlayer` when it is about to call `play()` on a live output
/// device. It hands back a player whose output stage is muted.
///
/// ## WHY the output is muted (do not regress)
/// The real-playback tests are hermetic — `GeneratedClipLibrary` encodes their
/// clips at test time — so they run by default under a plain `swift test`,
/// including the owner's UNATTENDED daily 07:00 CI job on their own Mac. At the
/// default volume that suite pushes roughly half a minute of tones and music
/// through the speakers every morning, unprompted. A test suite that makes noise
/// is a test suite people learn to stop running.
///
/// ## WHY muting cannot weaken a single assertion
/// `AVAudioEnginePlayer.volume` is `engine.mainMixerNode.outputVolume` — the
/// LAST stage of the graph. Everything these tests actually assert happens
/// upstream of it and is therefore untouched:
///
/// * the render clock (`currentTime`) counts frames the player node has
///   rendered; the mixer scaling them by zero afterwards does not stop them
///   being rendered, so "the clock advanced" still means real playback;
/// * `isPlaying` / `isEngineRunningForTesting` are engine lifecycle state;
/// * `sampleRateHz` / `channelCount` / `duration` come from the decoded file,
///   captured in `load`.
///
/// Only the speaker is spared. `SilentRealPlaybackTests` pins that claim.
///
/// ## The exception: tests that MEASURE the PCM tap
/// The one thing that is NOT upstream of the volume is the production PCM tap.
/// `AVAudioEnginePlayer` documents it as "POST-EQ, PRE-VOLUME", but that is the
/// intent, not the behaviour: the tap is installed on `mainMixerNode` bus 0,
/// which is the mixer's OUTPUT bus — after `outputVolume`. Measured on this
/// machine with the same fixture at three volumes, RMS scales exactly linearly
/// with the fader:
///
/// | volume | tap RMS  | delivered samples |
/// |--------|----------|-------------------|
/// | 0.00   | 0.0      | 14 400            |
/// | 0.25   | 0.088    | 14 400            |
/// | 1.00   | 0.353    | 14 400            |
///
/// So a test that asserts on tap ENERGY cannot use `makePlayer()`: muting it
/// would zero the very evidence it exists to collect (buffers still arrive —
/// only the samples are zeroed — so it would fail loudly rather than rot, but
/// it would fail). Those two tests use `tapMeasuringVolume` instead. Everything
/// else in the target is muted outright.
enum SilentRealPlayback {

    /// The output level for the ONLY tests that cannot be muted: the two that
    /// measure the live PCM tap, which sits after the volume fader (see above).
    ///
    /// It is a plain attenuation, not a compromise on evidence. Both assertions
    /// those tests make are scale-invariant — "the tap delivered signal at all"
    /// (`rms > 0`) and "a +12 dB band boost lifts its own tone by more than
    /// 6 dB" (a RATIO, in which any common factor cancels) — and at this level
    /// the captured peak is still ~25x the `1e-3` floor those measurements
    /// discard samples below, so nothing near the threshold moves. It only makes
    /// the ~1 s of tones those two tests emit about 26 dB quieter than the
    /// default, which is the most that can be done for them without deleting
    /// what they measure.
    static let tapMeasuringVolume: Float = 0.05

    /// A real `AVAudioEnginePlayer` with its output muted. Use this anywhere a
    /// test drives `play()` through the machine's real output device.
    ///
    /// Mute BEFORE handing the player to `PlayerCore`: the core reads
    /// `engine.volume` in its initializer and re-pushes that authoritative value
    /// to the engine on every `load`, so a core built from a muted player keeps
    /// the whole queue silent without any per-test `setVolume(0)`.
    static func makePlayer() -> AVAudioEnginePlayer {
        let player = AVAudioEnginePlayer()
        player.volume = 0
        return player
    }

    /// A real player attenuated to `tapMeasuringVolume` — for the two tests that
    /// measure the live PCM tap and therefore cannot be muted outright. Use
    /// `makePlayer()` everywhere else.
    static func makeTapMeasuringPlayer() -> AVAudioEnginePlayer {
        let player = AVAudioEnginePlayer()
        player.volume = tapMeasuringVolume
        return player
    }
}
