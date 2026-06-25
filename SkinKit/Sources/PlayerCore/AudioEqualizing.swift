import Foundation

// MARK: - AudioEqualizing

/// Opt-in equalizer sink, separate from transport.
///
/// Like `AudioTapProviding` and `TrackFormatProviding`, this is deliberately a
/// DISTINCT protocol from `AudioPlaybackEngine`: not every engine can apply a
/// graphic equalizer, and the DSP must never be modelled in `PlayerCore`'s
/// transport state. `PlayerCore` owns the authoritative `EQState` and, whenever
/// it changes, mirrors it to the engine by opt-in casting the injected engine to
/// this protocol (exactly how a consumer casts to `AudioTapProviding` to install
/// a tap) and calling `applyEqualizer`. An engine that does not conform simply
/// never receives EQ updates, so the equalizer state is inert — transport is
/// unaffected.
///
/// The protocol is platform-neutral (only the `Foundation`-only `EQState`, whose
/// payload is `Bool`/`Double`), so it lives in the pure core while the concrete,
/// `AVAudioUnitEQ`-backed implementation stays in the playback module.
///
/// ## Engine-coupling taxonomy
/// Two directions, deliberately kept apart: core-PUSHED state (volume, EQ) is
/// authoritative in `PlayerCore` and mirrored DOWN to the engine in a `didSet` /
/// setter (here, `applyEqualizer`); consumer-PULLED streams (the PCM tap, the
/// track format) are read UP from the engine by the shell/consumer via an opt-in
/// cast, never through `PlayerCore`'s transport.
///
/// - Note: `applyEqualizer` is the FULL, idempotent state: the engine should set
///   itself to exactly `state` (gains, preamp, and enabled/bypass), not apply a
///   delta. `PlayerCore` calls it with the complete current `EQState` on every
///   change.
public protocol AudioEqualizing: AnyObject {
    /// Apply the complete equalizer `state` to the engine's DSP. Idempotent: the
    /// engine sets itself to exactly `state`. When `state.enabled == false` the
    /// engine should pass audio through unchanged regardless of the gains.
    func applyEqualizer(_ state: EQState)
}
