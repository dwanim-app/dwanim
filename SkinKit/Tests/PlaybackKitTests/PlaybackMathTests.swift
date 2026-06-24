import AVFoundation
import XCTest
@testable import PlaybackKit

// MARK: - PlaybackMathTests

/// Deterministic unit tests for the pure frame/time helpers. No audio device,
/// no engine — just arithmetic.
final class PlaybackMathTests: XCTestCase {

    private let sampleRate = 44_100.0

    // MARK: - Round trips

    func testTimeToFrameToTimeRoundTrips() {
        for time in [0.0, 0.5, 1.0, 3.25, 12.7] {
            let frame = PlaybackMath.frame(forTime: time, sampleRate: sampleRate)
            let back = PlaybackMath.time(forFrame: frame, sampleRate: sampleRate)
            // Within one frame of error from rounding to integer frames.
            XCTAssertEqual(back, time, accuracy: 1.0 / sampleRate)
        }
    }

    func testFrameForTimeRoundsToNearestFrame() {
        // 1.0s at 44.1kHz is exactly frame 44_100.
        XCTAssertEqual(
            PlaybackMath.frame(forTime: 1.0, sampleRate: sampleRate),
            44_100
        )
    }

    // MARK: - Duration

    func testDurationMatchesFrameCountOverSampleRate() {
        XCTAssertEqual(
            PlaybackMath.duration(frames: 44_100, sampleRate: sampleRate),
            1.0,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            PlaybackMath.duration(frames: 88_200, sampleRate: sampleRate),
            2.0,
            accuracy: 1e-9
        )
    }

    // MARK: - Degenerate sample rate

    func testZeroSampleRateIsSafe() {
        XCTAssertEqual(PlaybackMath.frame(forTime: 5, sampleRate: 0), 0)
        XCTAssertEqual(PlaybackMath.time(forFrame: 5, sampleRate: 0), 0)
        XCTAssertEqual(PlaybackMath.duration(frames: 5, sampleRate: 0), 0)
    }

    // MARK: - Clamping

    func testClampNegativeGoesToZero() {
        XCTAssertEqual(PlaybackMath.clamp(-3, to: 10), 0)
    }

    func testClampBeyondUpperBoundGoesToBound() {
        XCTAssertEqual(PlaybackMath.clamp(42, to: 10), 10)
    }

    func testClampInRangeIsUnchanged() {
        XCTAssertEqual(PlaybackMath.clamp(4.5, to: 10), 4.5)
    }

    func testClampWithEmptyDurationIsZero() {
        XCTAssertEqual(PlaybackMath.clamp(4.5, to: 0), 0)
        XCTAssertEqual(PlaybackMath.clamp(-1, to: 0), 0)
    }

    // MARK: - Non-finite input (must never trap downstream)

    func testClampMapsNaNToZeroAndInfinitiesToBounds() {
        XCTAssertEqual(PlaybackMath.clamp(.nan, to: 10), 0)
        XCTAssertEqual(PlaybackMath.clamp(.infinity, to: 10), 10)
        XCTAssertEqual(PlaybackMath.clamp(-.infinity, to: 10), 0)
    }

    func testFrameForNonFiniteTimeIsZero() {
        // Guards the AVAudioFramePosition (Int64) conversion, which traps on
        // NaN/inf — the root of the seek(to: NaN) crash.
        XCTAssertEqual(PlaybackMath.frame(forTime: .nan, sampleRate: sampleRate), 0)
        XCTAssertEqual(PlaybackMath.frame(forTime: .infinity, sampleRate: sampleRate), 0)
        XCTAssertEqual(PlaybackMath.frame(forTime: -.infinity, sampleRate: sampleRate), 0)
    }
}
