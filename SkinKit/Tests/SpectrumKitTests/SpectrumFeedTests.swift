import XCTest
@testable import SpectrumKit

/// Contract tests for `SpectrumFeed`, the lock-guarded latest-samples handoff
/// between the audio render thread (writer) and the main thread (reader). These
/// pin the exact semantics lifted from the harness's former `LatestSamples` /
/// `DefaultSkinLatestSamples` boxes: empty-before-first-write, latest-wins, and
/// concurrent set/get safety.
final class SpectrumFeedTests: XCTestCase {

    // MARK: - Empty before first write

    func testEmptyBeforeFirstWrite() {
        let feed = SpectrumFeed()
        let snapshot = feed.latest()
        XCTAssertTrue(snapshot.samples.isEmpty, "No samples should be present before the first store.")
        XCTAssertEqual(snapshot.sampleRate, 44_100, "The default sample rate is 44_100 before any store.")
    }

    // MARK: - Store / read round-trip

    func testStoreThenReadReturnsTheStoredFrame() {
        let feed = SpectrumFeed()
        feed.store([0.1, 0.2, 0.3], sampleRate: 48_000)
        let snapshot = feed.latest()
        XCTAssertEqual(snapshot.samples, [0.1, 0.2, 0.3])
        XCTAssertEqual(snapshot.sampleRate, 48_000)
    }

    // MARK: - Latest wins

    func testLatestWriteOverwritesEarlierFrames() {
        let feed = SpectrumFeed()
        feed.store([1, 2, 3], sampleRate: 22_050)
        feed.store([4, 5], sampleRate: 96_000)
        feed.store([7], sampleRate: 8_000)
        let snapshot = feed.latest()
        XCTAssertEqual(snapshot.samples, [7], "Only the most recent stored frame is kept.")
        XCTAssertEqual(snapshot.sampleRate, 8_000, "The most recent sample rate is kept.")
    }

    func testReadingTwiceWithoutWritingReturnsTheSameFrame() {
        let feed = SpectrumFeed()
        feed.store([0.5, 0.6], sampleRate: 44_100)
        let first = feed.latest()
        let second = feed.latest()
        XCTAssertEqual(first.samples, second.samples)
        XCTAssertEqual(first.sampleRate, second.sampleRate)
    }

    // MARK: - Empty store is honored

    func testStoringAnEmptyFrameIsHonored() {
        let feed = SpectrumFeed()
        feed.store([1, 2, 3], sampleRate: 44_100)
        feed.store([], sampleRate: 44_100)
        XCTAssertTrue(feed.latest().samples.isEmpty, "An explicitly stored empty frame overwrites a prior one.")
    }

    // MARK: - Concurrent set/get safety

    /// Hammer the feed from many concurrent writers while a reader pulls
    /// snapshots, asserting that every read returns a self-consistent frame (the
    /// samples and sample rate come from the SAME store, never a torn mix). Each
    /// writer stores a frame whose every sample equals its sample-rate marker, so
    /// a torn read would surface as a sample that disagrees with the rate.
    func testConcurrentStoreAndReadAreConsistent() {
        let feed = SpectrumFeed()
        feed.store([1_000], sampleRate: 1_000)

        let iterations = 5_000
        let writeGroup = DispatchGroup()

        // Reader: continuously snapshot and verify internal consistency.
        let readerDone = expectation(description: "reader finished")
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                let snapshot = feed.latest()
                // Every sample in a stored frame equals the frame's marker rate;
                // a torn read would break that invariant.
                if let first = snapshot.samples.first {
                    XCTAssertEqual(
                        Double(first), snapshot.sampleRate,
                        "A read returned a sample that does not match its sample rate (torn read)."
                    )
                }
            }
            readerDone.fulfill()
        }

        // Writers: each stores a self-consistent (sample == rate) frame.
        for w in 0..<8 {
            writeGroup.enter()
            DispatchQueue.global().async {
                for i in 0..<iterations {
                    let marker = Double((w + 1) * 1_000 + (i % 7))
                    feed.store([Float(marker)], sampleRate: marker)
                }
                writeGroup.leave()
            }
        }

        writeGroup.wait()
        wait(for: [readerDone], timeout: 30)

        // Final snapshot is still self-consistent.
        let final = feed.latest()
        if let first = final.samples.first {
            XCTAssertEqual(Double(first), final.sampleRate)
        }
    }
}
