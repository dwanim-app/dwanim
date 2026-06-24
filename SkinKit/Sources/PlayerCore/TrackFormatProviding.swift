import Foundation

// MARK: - TrackFormatProviding

/// Opt-in source of the loaded track's audio FORMAT facts (sample rate and
/// bitrate), separate from transport.
///
/// Like `AudioTapProviding`, this is deliberately a DISTINCT protocol from
/// `AudioPlaybackEngine`: format metadata is not transport state and must never
/// be routed through `PlayerCore`. A consumer that wants to show the classic
/// kbps / kHz number boxes — e.g. the render harness — opt-in casts the engine
/// to this protocol and reads the two values each redraw.
///
/// The protocol is platform-neutral (only `Double`/`Int`) so it can live in the
/// Foundation-only core while the concrete, framework-backed implementation
/// stays in the playback module.
///
/// Both values are `0` when nothing is loaded, or when the value is unknown for
/// the loaded file (e.g. a container that does not expose an estimated data
/// rate). A consumer treats `0` as "blank / no reading".
public protocol TrackFormatProviding: AnyObject {
    /// The loaded file's sample rate, in Hz (e.g. `44_100`). `0` when unknown or
    /// nothing is loaded. The kHz box shows `round(sampleRateHz / 1000)`.
    var sampleRateHz: Double { get }

    /// The loaded file's bitrate, in kbps (kilobits per second). `0` when
    /// unknown or nothing is loaded. A lossless/uncompressed source reports its
    /// large effective rate (e.g. ~1411 kbps for 44.1k/16-bit/stereo).
    var bitrateKbps: Int { get }
}
