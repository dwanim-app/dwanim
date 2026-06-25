import AVFoundation
import Foundation
import PlayerCore

// MARK: - EQConfig

/// The production configuration of the 10-band graphic equalizer's
/// `AVAudioUnitEQ`: the classic centre frequencies, filter type, bandwidth, and
/// the routine that maps an `EQState` onto the unit.
///
/// This is factored out of `AVAudioEnginePlayer` so the offline DSP-proof test
/// can build an `AVAudioUnitEQ` configured *identically* to production and prove
/// the real band setup changes the sound — rather than a test-only EQ that might
/// drift from what ships.
enum EQConfig {

    // MARK: - Bands

    /// The classic 10-band graphic-equalizer centre frequencies, in Hz, low to
    /// high. Index `i` here corresponds to `EQState.bands[i]`.
    static let centreFrequencies: [Float] = [
        60, 170, 310, 600, 1_000, 3_000, 6_000, 12_000, 14_000, 16_000
    ]

    /// Bandwidth in octaves for each parametric (peaking) band. ~1 octave is a
    /// musically sensible width for a graphic EQ: wide enough that adjacent
    /// bands overlap into a smooth response, narrow enough that a single-band
    /// boost is clearly localized in frequency.
    static let bandwidthOctaves: Float = 1.0

    // MARK: - Configuration

    /// Pins `unit`'s bands to the classic centre frequencies as parametric
    /// (peaking) filters at unity gain, active (not bypassed). Call once at
    /// graph-construction time; afterwards only the gains and `globalGain`
    /// change via `apply(_:to:)`. The `unit` must have been created with
    /// `numberOfBands == centreFrequencies.count`.
    static func configure(_ unit: AVAudioUnitEQ) {
        for (index, frequency) in centreFrequencies.enumerated() {
            let band = unit.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = bandwidthOctaves
            band.gain = 0
            band.bypass = false
        }
        unit.globalGain = 0
    }

    /// Applies the equalizer `state` to a configured `unit` (idempotent).
    ///
    /// - When `state.enabled == false`: every band is bypassed and `globalGain`
    ///   is reset to `0`, so the unit passes audio through unchanged regardless
    ///   of the dialed-in gains.
    /// - When `state.enabled == true`: each band's gain is set from
    ///   `state.bands[i]` (and un-bypassed) and `globalGain` is set to
    ///   `state.preamp`.
    ///
    /// `state.bands` is assumed `EQState.bandCount`-long (guaranteed by
    /// `EQState`), but the loop is bounded by the unit's band count for safety.
    static func apply(_ state: EQState, to unit: AVAudioUnitEQ) {
        let count = min(unit.bands.count, state.bands.count)
        if state.enabled {
            for index in 0..<count {
                let band = unit.bands[index]
                band.bypass = false
                band.gain = Float(state.bands[index])
            }
            unit.globalGain = Float(state.preamp)
        } else {
            for index in 0..<count {
                unit.bands[index].bypass = true
            }
            unit.globalGain = 0
        }
    }
}
