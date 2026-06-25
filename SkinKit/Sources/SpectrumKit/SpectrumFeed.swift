import Foundation

// MARK: - SpectrumFeed

/// The single point of contact between the audio render thread (which produces
/// PCM in a tap) and the main thread (which consumes it in a redraw timer).
///
/// The tap does the MINIMUM on the audio thread: it just stashes the most recent
/// mono frame + sample rate under a lock. No analysis, no allocation beyond the
/// frame copy, no UI. The main thread reads the latest snapshot and runs the FFT
/// (`SpectrumAnalyzer`).
///
/// An `NSLock` (not a serial queue) keeps the audio-thread critical section tiny
/// and non-blocking-ish — store/read a small struct and return. Only the latest
/// frame is kept (older frames are simply overwritten); the analyzer always wants
/// the most recent window, so dropping stale frames is correct, not lossy.
///
/// Pure Foundation: no AppKit, no AVFoundation, no platform types. The audio
/// thread is responsible for thread-hopping before touching UI; this box only
/// hands the latest samples across the seam.
public final class SpectrumFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 44_100

    /// Create an empty feed. Before the first `store`, `latest()` returns an empty
    /// sample array and the default `44_100` sample rate.
    public init() {}

    /// Audio-thread entry point: overwrite the stashed frame. Tiny critical
    /// section — copy the array reference and the rate, then return. A later
    /// `store` overwrites the earlier one (latest-wins).
    public func store(_ samples: [Float], sampleRate: Double) {
        lock.lock()
        self.samples = samples
        self.sampleRate = sampleRate
        lock.unlock()
    }

    /// Main-thread entry point: read the latest stashed frame + rate. Before any
    /// `store` this is `(samples: [], sampleRate: 44_100)`.
    public func latest() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, sampleRate)
    }
}
