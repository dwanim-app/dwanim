import AVFoundation
import Foundation

// MARK: - PlaybackMath

/// Pure, deterministic conversions between sample frames and wall-clock time.
///
/// These helpers carry no engine state, so they can be unit-tested directly
/// without an audio device. The concrete engine delegates all of its
/// frame/time arithmetic here to keep the stateful code thin and the math
/// verifiable.
enum PlaybackMath {

    // MARK: - Conversions

    /// The sample frame corresponding to an absolute `time` in seconds.
    ///
    /// Returns `0` for a non-positive sample rate so callers never divide by,
    /// or multiply against, a degenerate rate.
    static func frame(
        forTime time: TimeInterval,
        sampleRate: Double
    ) -> AVAudioFramePosition {
        guard sampleRate > 0 else { return 0 }
        let frames = (time * sampleRate).rounded()
        return AVAudioFramePosition(frames)
    }

    /// The absolute time in seconds corresponding to a sample `frame`.
    static func time(
        forFrame frame: AVAudioFramePosition,
        sampleRate: Double
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(frame) / sampleRate
    }

    /// The duration in seconds of a file `frames` long at `sampleRate`.
    static func duration(
        frames: AVAudioFramePosition,
        sampleRate: Double
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(frames) / sampleRate
    }

    // MARK: - Clamping

    /// Clamps `value` to the inclusive `0...upperBound` range.
    ///
    /// A negative or zero `upperBound` collapses the range to `0`, so an
    /// out-of-range seek on an empty file resolves to the start.
    static func clamp(
        _ value: TimeInterval,
        to upperBound: TimeInterval
    ) -> TimeInterval {
        guard upperBound > 0 else { return 0 }
        return Swift.min(Swift.max(value, 0), upperBound)
    }
}
