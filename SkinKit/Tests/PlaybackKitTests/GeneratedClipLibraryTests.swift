import AVFoundation
import Foundation
import XCTest
@testable import PlaybackKit

// MARK: - GeneratedClipLibraryTests

/// The generator's own guard. It runs on every machine, with no environment
/// variable and no clips, and it is what keeps the hermetic fixture set honest:
/// `GeneratedClipLibrary.directory()` already opens and format-checks every file
/// it produces, so these assert the MATRIX still covers what the acceptance test
/// needs it to cover.
@MainActor
final class GeneratedClipLibraryTests: XCTestCase {

    func testTheGeneratedSetIsBuiltAndEveryRowOpensAtItsDeclaredFormat() throws {
        // `directory()` verifies each file before returning; reaching here at all
        // means all eight encoded and opened at their declared rate/channels.
        let directory = try GeneratedClipLibrary.directory()
        for spec in GeneratedClipLibrary.matrix {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(spec.name).path
                ),
                "\(spec.name) is missing from the generated set"
            )
        }
    }

    /// The matrix must keep crossing both boundaries the format-change fix is
    /// about. A set that quietly became all-44.1k-stereo would still pass every
    /// assertion in the acceptance test while proving nothing.
    func testTheMatrixCoversBothSampleRatesAndBothChannelCounts() {
        let rates = Set(GeneratedClipLibrary.matrix.map(\.sampleRate))
        let channels = Set(GeneratedClipLibrary.matrix.map(\.channels))
        XCTAssertEqual(rates, [44_100, 48_000], "both sample rates must appear")
        XCTAssertEqual(channels, [1, 2], "both mono and stereo must appear")

        let containers = Set(GeneratedClipLibrary.matrix.map(\.fileFormat))
        XCTAssertTrue(containers.isSuperset(of: ["flac", "WAVE", "AIFF", "m4af", "caff"]),
                      "the set must span real containers, not one repeated: \(containers)")
        let codecs = Set(GeneratedClipLibrary.matrix.map(\.dataFormat))
        XCTAssertTrue(codecs.isSuperset(of: ["flac", "aac", "alac"]),
                      "the set must span real codecs, not PCM only: \(codecs)")
    }

    /// Adjacent rows must actually cross boundaries — that is the whole point of
    /// walking the queue by hand rather than playing one file.
    func testAdjacentRowsCrossRateAndChannelBoundaries() {
        let matrix = GeneratedClipLibrary.matrix
        let steps = zip(matrix, matrix.dropFirst())
        let rateChanges = steps.filter { $0.sampleRate != $1.sampleRate }.count
        let channelChanges = zip(matrix, matrix.dropFirst())
            .filter { $0.channels != $1.channels }.count
        XCTAssertGreaterThanOrEqual(rateChanges, 4, "forward steps crossing a sample-rate change")
        XCTAssertGreaterThanOrEqual(channelChanges, 2, "forward steps crossing a channel change")
    }

    /// The hollow clip is the "opens but renders nothing" negative. Both halves
    /// of that are asserted: it OPENS (a corrupt file would throw and take the
    /// other recovery path), and it promises far more audio than it holds.
    func testTheHollowClipOpensAndPromisesAudioItDoesNotHold() throws {
        let url = try GeneratedClipLibrary.hollowClip()
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.processingFormat.sampleRate, 44_100)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        XCTAssertGreaterThan(Double(file.length) / file.processingFormat.sampleRate, 60,
                             "the container must claim far more audio than the file holds")

        let onDisk = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        ).intValue
        XCTAssertLessThan(onDisk, 1024,
                          "and hold essentially none of it — \(onDisk) bytes")
    }

    /// The other negative: bytes no decoder accepts.
    func testTheDeadFileIsWrittenAndIsNotAudio() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwanim-deadfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try GeneratedClipLibrary.deadFile("broken.mp3", in: directory)
        XCTAssertThrowsError(try AVAudioFile(forReading: url),
                             "the dead file must be undecodable")
    }
}
