import Foundation

// MARK: - EQState

/// The pure, UI- and framework-agnostic state of a classic 10-band graphic
/// equalizer: an on/off switch, a preamp gain, and one gain per band.
///
/// All gains are **decibels**, clamped to the classic `-12...+12 dB` range, and a
/// fresh value is **flat** (every gain `0`) and **disabled** (`enabled == false`),
/// so an untouched equalizer is a perfect pass-through. The type is
/// `Foundation`-only (`Bool`/`Double` payloads), so it can live in the pure core
/// and travel to the audio engine across the platform-neutral `AudioEqualizing`
/// boundary without dragging in any audio framework.
///
/// ## Why values, not setters that mutate the engine
/// `EQState` is a plain value type with no engine reference. `PlayerCore` owns the
/// authoritative copy as observable state and is the single place that mirrors a
/// change to the engine (exactly how `setVolume` flows). Keeping `EQState` a
/// value keeps it trivially `Equatable`/`Sendable` and unit-testable in isolation.
///
/// ## Clamping contract
/// - `setPreamp` / `setBand` clamp the dB into `gainRange` (`-12...+12`).
/// - A non-finite gain (`NaN`/`±inf`) is **ignored** as a no-op: clamping cannot
///   sanitize it (`min(max(NaN, lo), hi)` is `NaN`) and pushing it to a real
///   equalizer is undefined. This mirrors `PlayerCore.setVolume`'s `isFinite`
///   guard.
/// - `setBand` is **bounds-checked**: an out-of-range index is a guarded no-op,
///   so a caller can never corrupt the fixed 10-element `bands` array.
public struct EQState: Equatable, Sendable {

    // MARK: - Constants

    /// The number of bands in the classic graphic equalizer.
    public static let bandCount = 10

    /// The inclusive dB range every gain (preamp and each band) is clamped to.
    /// `-12...+12 dB` is the classic graphic-equalizer range.
    public static let gainRange: ClosedRange<Double> = -12...12

    // MARK: - Stored state

    /// Whether the equalizer is active. When `false`, the engine should pass
    /// audio through unchanged regardless of the gains below.
    public var enabled: Bool

    /// The pre-amplifier gain in dB, applied to the whole signal. Clamped to
    /// `gainRange`.
    public private(set) var preamp: Double

    /// The per-band gains in dB, one per `bandCount` band, low frequency first.
    /// Each is clamped to `gainRange`. The array always has exactly `bandCount`
    /// elements.
    public private(set) var bands: [Double]

    // MARK: - Init

    /// Creates a flat, disabled equalizer: `enabled == false`, `preamp == 0`,
    /// and every band `0`. This is the default / pass-through state.
    public init() {
        self.enabled = false
        self.preamp = 0
        self.bands = [Double](repeating: 0, count: EQState.bandCount)
    }

    /// Creates an equalizer from explicit values, applying the same clamping the
    /// setters use so an out-of-range argument can never produce an invalid
    /// state. A `bands` array shorter or longer than `bandCount` is resized
    /// (padded with `0` / truncated) so `bands.count == bandCount` always holds.
    /// Non-finite gains fall back to `0`.
    public init(enabled: Bool, preamp: Double, bands: [Double]) {
        self.enabled = enabled
        self.preamp = EQState.clamp(preamp)
        var resized = [Double](repeating: 0, count: EQState.bandCount)
        for index in 0..<EQState.bandCount where index < bands.count {
            resized[index] = EQState.clamp(bands[index])
        }
        self.bands = resized
    }

    // MARK: - Clamping setters

    /// Sets the preamp gain, clamped to `gainRange`. A non-finite value is
    /// ignored (no-op), matching the engine's undefined-input policy.
    public mutating func setPreamp(_ dB: Double) {
        guard dB.isFinite else { return }
        preamp = EQState.clamp(dB)
    }

    /// Sets band `index`'s gain in dB, clamped to `gainRange`. An out-of-range
    /// index or a non-finite value is a guarded no-op, so the fixed-size `bands`
    /// array can never be corrupted.
    public mutating func setBand(_ index: Int, dB: Double) {
        guard bands.indices.contains(index) else { return }
        guard dB.isFinite else { return }
        bands[index] = EQState.clamp(dB)
    }

    // MARK: - Helpers

    /// Clamps a finite dB value into `gainRange`. Callers guard `isFinite` first.
    private static func clamp(_ dB: Double) -> Double {
        min(max(dB, gainRange.lowerBound), gainRange.upperBound)
    }
}
