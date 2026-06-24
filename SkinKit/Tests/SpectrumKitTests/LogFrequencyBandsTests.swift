import XCTest
@testable import SpectrumKit

// MARK: - LogFrequencyBandsTests

/// Unit tests for the pure log-frequency band mapping that turns a continuous
/// frequency into a bar index and exposes the band edges used for grouping
/// FFT bins.
final class LogFrequencyBandsTests: XCTestCase {

    func testEdgesAreMonotonicAndSpanRange() {
        let bands = LogFrequencyBands(barCount: 20, sampleRate: 44_100)
        let edges = bands.edges
        XCTAssertEqual(edges.count, 21) // barCount + 1 edges
        for i in 1..<edges.count {
            XCTAssertGreaterThan(edges[i], edges[i - 1])
        }
        XCTAssertEqual(edges.first!, 20, accuracy: 1e-6)         // 20 Hz floor
        XCTAssertEqual(edges.last!, 44_100 / 2, accuracy: 1e-6)  // Nyquist
    }

    func testLowFrequencyMapsToFirstBar() {
        let bands = LogFrequencyBands(barCount: 20, sampleRate: 44_100)
        XCTAssertEqual(bands.bar(forFrequency: 20), 0)
        XCTAssertEqual(bands.bar(forFrequency: 5), 0) // below floor clamps to 0
    }

    func testHighFrequencyMapsToLastBar() {
        let barCount = 20
        let bands = LogFrequencyBands(barCount: barCount, sampleRate: 44_100)
        XCTAssertEqual(bands.bar(forFrequency: 22_050), barCount - 1)
        XCTAssertEqual(bands.bar(forFrequency: 40_000), barCount - 1) // above Nyquist clamps
    }

    func testFrequencyFallsWithinItsBarEdges() {
        let bands = LogFrequencyBands(barCount: 20, sampleRate: 44_100)
        let f = 1_000.0
        let bar = bands.bar(forFrequency: f)
        XCTAssertGreaterThanOrEqual(f, bands.edges[bar])
        XCTAssertLessThanOrEqual(f, bands.edges[bar + 1])
    }

    func testSingleBarSpansWholeRange() {
        let bands = LogFrequencyBands(barCount: 1, sampleRate: 44_100)
        XCTAssertEqual(bands.bar(forFrequency: 20), 0)
        XCTAssertEqual(bands.bar(forFrequency: 1_000), 0)
        XCTAssertEqual(bands.bar(forFrequency: 22_050), 0)
    }
}
