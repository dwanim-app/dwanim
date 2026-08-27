import Foundation
import XCTest
@testable import PlaybackKit

// MARK: - TrackDurationLoaderTests

/// Tests for `TrackDurationLoader.duration(of:)`, the async `AVURLAsset`-backed
/// read that fills the playlist Time column for every queued file. Driven with a
/// synthesized sine WAV of a known length (`SineWAVFactory`, shared with the
/// engine tests) so the assertion never depends on any external audio asset.
final class TrackDurationLoaderTests: XCTestCase {

    func testReadsKnownWAVDuration() async throws {
        let url = try SineWAVFactory.write(duration: 2.0, sampleRate: 44_100)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = await TrackDurationLoader.duration(of: url)
        let seconds = try XCTUnwrap(loaded)

        // AVFoundation reports the container duration; a small tolerance covers
        // the header/frame rounding.
        XCTAssertEqual(seconds, 2.0, accuracy: 0.05)
    }

    func testShorterFileReadsShorterDuration() async throws {
        let url = try SineWAVFactory.write(duration: 0.5, sampleRate: 44_100)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = await TrackDurationLoader.duration(of: url)
        let seconds = try XCTUnwrap(loaded)

        XCTAssertEqual(seconds, 0.5, accuracy: 0.05)
    }

    func testUnreadableURLIsNil() async {
        // A path with no file behind it: the asset load fails → nil (row keeps "—").
        let missing = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        let seconds = await TrackDurationLoader.duration(of: missing)

        XCTAssertNil(seconds)
    }

    func testNonAudioBytesAreNil() async throws {
        // A file that exists but is not decodable media → nil, not a bogus 0.
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let seconds = await TrackDurationLoader.duration(of: url)

        XCTAssertNil(seconds)
    }
}
