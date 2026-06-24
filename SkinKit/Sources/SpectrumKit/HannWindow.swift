import Foundation
import Accelerate

// MARK: - HannWindow

/// A precomputed periodic Hann window of a fixed length, used to taper an
/// audio frame before the FFT so spectral leakage from the frame edges is
/// suppressed.
///
/// The window is computed once at init (via `vDSP`) and reused for every
/// frame, since the frame length is fixed for the lifetime of the analyzer.
struct HannWindow {

    // MARK: - Stored properties

    /// The Hann coefficients, one per sample in the frame.
    let coefficients: [Float]

    // MARK: - Init

    init(length: Int) {
        let count = max(1, length)
        var window = [Float](repeating: 0, count: count)
        // Periodic (D = .HANN_DENORM, no half-shift) Hann window matched to
        // FFT analysis; `vDSP_hann_window` fills it in one call.
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        self.coefficients = window
    }

    // MARK: - Apply

    /// Returns `frame` multiplied element-wise by the window. `frame.count`
    /// must equal the window length.
    func applied(to frame: [Float]) -> [Float] {
        precondition(frame.count == coefficients.count,
                     "frame length must match window length")
        return vDSP.multiply(frame, coefficients)
    }
}
