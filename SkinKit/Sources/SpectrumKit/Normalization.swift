import Foundation

// MARK: - Normalization

/// Maps a linear FFT-bin magnitude to a perceptual `0...1` bar level on a
/// **decibel** scale against a fixed full-scale reference.
///
/// ## Reference choice (documented)
/// The FFT and analysis window are unnormalized, so a tone's bin magnitude
/// scales with `fftSize`. A full-scale sine (amplitude `1.0`) through the
/// normalized Hann window and `vDSP`'s packed real FFT peaks at roughly
/// `fftSize / 2` in linear magnitude; that value is used as the 0 dB reference
/// so a full-scale tone reads near `1.0`.
///
/// Levels are expressed in dB relative to that reference and mapped linearly
/// across a `floorDB` dynamic range onto `0...1`:
/// - `0 dB` (full-scale) -> `1.0`
/// - `<= floorDB` (very quiet / silence) -> `0.0`
///
/// True silence (magnitude `0`) maps to `0` directly, avoiding `log(0)`.
enum Normalization {

    // MARK: - Constants

    /// Bottom of the displayed dynamic range, in dB. Magnitudes at or below
    /// this read as `0`. ~60 dB gives a lively but not noisy classic display.
    static let floorDB: Float = -60

    // MARK: - Mapping

    /// The `0...1` level for a linear `magnitude` produced from a frame of the
    /// given `fftSize`.
    static func level(forMagnitude magnitude: Float, fftSize: Int) -> Float {
        guard magnitude > 0 else { return 0 }

        let reference = Float(fftSize) / 2
        let db = 20 * log10(magnitude / reference)
        guard db > floorDB else { return 0 }

        let level = (db - floorDB) / -floorDB // floorDB..0 -> 0..1
        return min(max(level, 0), 1)
    }
}
