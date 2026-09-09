import AVFoundation
import Foundation

// MARK: - GeneratedClipLibrary
//
// The acceptance queue's audio, MADE AT TEST TIME.
//
// ## Why this exists
// `RealQueueTransportClickThroughTests` is the strongest evidence in the suite:
// real containers, the real `AVAudioEnginePlayer`, real clicks on the real
// buttons, and a per-step assertion that the render clock actually moves across
// every 44.1k<->48k and mono<->stereo boundary. It used to run only when
// `DWANIM_REAL_CLIPS` pointed at the owner's downloaded music, so the daily CI —
// a plain `swift test` — skipped it every single night. A permanently skipped
// acceptance test is worse than no acceptance test: it never goes red, so it
// goes on reading like proof.
//
// Committing the owner's clips was not an option either. They are real music
// under CC BY / CC BY-SA / PD terms, which would put attribution obligations on
// an MIT repository, and several megabytes of audio in git for one test.
//
// So the fixtures are ENCODED HERE, into a temp directory, by `afconvert` (the
// system encoder, present on every macOS) from PCM this file synthesizes. They
// are real encodes in real containers — a genuine FLAC, a genuine AAC bitstream
// — not renamed PCM, so the decoder under test does real work.
//
// ## What the matrix covers
// The same crossings the owner's set covers, in the same order, so every
// assertion the test makes about rate/channel changes still has something to
// bite on:
//
//   01 flac      44.1k stereo
//   02 wav       44.1k stereo
//   03 aac-adts  44.1k stereo
//   04 aiff      48k   stereo   [rate change]
//   05 aac-m4a   48k   mono     [channel change]
//   06 alac-m4a  44.1k mono     [rate change]
//   07 caf-alac  48k   mono     [rate change]
//   08 caf-pcm   44.1k stereo   [rate AND channel change]
//
// Containers: FLAC, WAVE, ADTS, AIFF, MPEG-4 (AAC and ALAC), CAF (ALAC and
// LPCM). Both sample rates and both channel counts appear on both sides of a
// boundary. The one format in the owner's set with no system ENCODER is MP3;
// row 03 covers that slot with a raw AAC bitstream instead, which keeps the
// step 02 -> 03 -> 04 rate/channel pattern identical.
//
// Two negatives complete the set, because the walk-recovery paths need them:
//   * `hollowClipName` — a file the decoder OPENS and cannot read a frame from.
//   * `deadFile(_:in:)` — bytes no decoder will accept at all.
//
// ## The hollow clip
// The owner's equivalent is an Ogg-wrapped FLAC that `AVAudioFile` opens, claims
// 100.5 s for, and then drains in ~18 ms without rendering anything — the case
// `PlayerCore.finishLooksLikeSilence` exists for, and the one a merely CORRUPT
// file cannot reach (a corrupt file throws on load and takes the other path).
// Reproducing it hermetically means building a container whose HEADER promises
// audio the file does not contain, which is exactly what a hand-written CAF can
// do: a `desc` chunk describing 44.1 kHz stereo 16-bit PCM, and a `data` chunk
// whose declared size claims 100.5 s while the file ends immediately after it.
// `AVAudioFile` reports 4,432,050 frames; reading returns nothing.
@MainActor
enum GeneratedClipLibrary {

    // MARK: - The matrix

    /// One generated fixture: what to encode, and what the ENGINE must report
    /// once it has loaded the result.
    struct Spec {
        let name: String
        let sampleRate: Double
        let channels: Int
        /// `afconvert -f` — the container.
        let fileFormat: String
        /// `afconvert -d` — the codec / sample format inside it.
        let dataFormat: String
    }

    /// The eight queue rows, in the order the transport buttons walk them.
    static let matrix: [Spec] = [
        Spec(name: "01_flac_gen_44k_stereo.flac",
             sampleRate: 44_100, channels: 2, fileFormat: "flac", dataFormat: "flac"),
        Spec(name: "02_wav_gen_44k_stereo.wav",
             sampleRate: 44_100, channels: 2, fileFormat: "WAVE", dataFormat: "LEI16"),
        Spec(name: "03_aac-raw_gen_44k_stereo.aac",
             sampleRate: 44_100, channels: 2, fileFormat: "adts", dataFormat: "aac"),
        Spec(name: "04_aiff_gen_48k_stereo.aiff",
             sampleRate: 48_000, channels: 2, fileFormat: "AIFF", dataFormat: "BEI16"),
        Spec(name: "05_aac-m4a_gen_48k_mono.m4a",
             sampleRate: 48_000, channels: 1, fileFormat: "m4af", dataFormat: "aac"),
        Spec(name: "06_alac-m4a_gen_44k_mono.m4a",
             sampleRate: 44_100, channels: 1, fileFormat: "m4af", dataFormat: "alac"),
        Spec(name: "07_caf-alac_gen_48k_mono.caf",
             sampleRate: 48_000, channels: 1, fileFormat: "caff", dataFormat: "alac"),
        Spec(name: "08_caf-pcm_gen_44k_stereo.caf",
             sampleRate: 44_100, channels: 2, fileFormat: "caff", dataFormat: "LEI16")
    ]

    /// The negative that OPENS and renders nothing.
    static let hollowClipName = "N_hollow_gen_44k_stereo.caf"

    /// How much audio each generated clip holds. Long enough that no clip can
    /// finish naturally in the middle of a click-through step (the longest a
    /// single track stays current is about a second), short enough to encode
    /// eight of them quickly.
    static let clipSeconds: Double = 6

    // MARK: - Building

    enum GenerationError: Error, CustomStringConvertible {
        case encoderMissing(String)
        case encodeFailed(name: String, status: Int32, output: String)
        case unreadable(name: String, underlying: String)
        case wrongFormat(name: String, expected: String, actual: String)

        var description: String {
            switch self {
            case .encoderMissing(let path):
                return "the system audio encoder is missing at \(path)"
            case .encodeFailed(let name, let status, let output):
                return "afconvert failed for \(name) (status \(status)): \(output)"
            case .unreadable(let name, let underlying):
                return "the generated \(name) could not be opened: \(underlying)"
            case .wrongFormat(let name, let expected, let actual):
                return "the generated \(name) is \(actual), not \(expected)"
            }
        }
    }

    /// The directory holding the generated set, built on first use and reused
    /// for the rest of the process (and, since the path is deterministic, across
    /// runs on the same machine — a set that is complete and still opens is not
    /// re-encoded).
    static func directory() throws -> URL {
        if let cached { return cached }
        let url = try build()
        cached = url
        return url
    }

    /// The hollow clip inside the generated set.
    static func hollowClip() throws -> URL {
        try directory().appendingPathComponent(hollowClipName)
    }

    /// A file of bytes no decoder accepts — the OTHER negative, for the
    /// load-throws recovery path. Written into `directory` (a caller-owned temp
    /// directory) rather than the shared fixture set, because each test wants
    /// its own.
    static func deadFile(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0, count: 4096).write(to: url)
        return url
    }

    private static var cached: URL?

    /// Bumped whenever `matrix`, `clipSeconds` or the synthesis changes, so a
    /// stale set from an older revision is never reused.
    private static let revision = "v1"

    private static func build() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwanim-generated-clips-\(revision)", isDirectory: true)

        if let existing = try? verify(root) { return existing }

        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // One PCM source per distinct (rate, channels) pair; every encode below
        // is a straight transcode of the matching source, so afconvert never
        // resamples or down-mixes and the engine really does see the rate and
        // channel count the matrix claims.
        var sources: [String: URL] = [:]
        for spec in matrix {
            let key = "\(Int(spec.sampleRate))-\(spec.channels)"
            guard sources[key] == nil else { continue }
            let url = root.appendingPathComponent("source-\(key).wav")
            try writeTone(to: url, sampleRate: spec.sampleRate, channels: spec.channels)
            sources[key] = url
        }

        for spec in matrix {
            let source = sources["\(Int(spec.sampleRate))-\(spec.channels)"]!
            try encode(source, to: root.appendingPathComponent(spec.name), as: spec)
        }

        try writeHollowCAF(
            to: root.appendingPathComponent(hollowClipName),
            sampleRate: 44_100, channels: 2, claimedSeconds: 100.5
        )

        for url in sources.values { try? FileManager.default.removeItem(at: url) }
        return try verify(root)
    }

    /// Every generated file is opened and its format checked before the set is
    /// handed out — a fixture that silently encoded at the wrong rate would turn
    /// the acceptance test's rate assertions into noise.
    @discardableResult
    private static func verify(_ root: URL) throws -> URL {
        for spec in matrix {
            let url = root.appendingPathComponent(spec.name)
            let file: AVAudioFile
            do { file = try AVAudioFile(forReading: url) }
            catch { throw GenerationError.unreadable(name: spec.name, underlying: "\(error)") }

            let format = file.processingFormat
            let actual = "\(Int(format.sampleRate)) Hz / \(format.channelCount) ch"
            let expected = "\(Int(spec.sampleRate)) Hz / \(spec.channels) ch"
            guard format.sampleRate == spec.sampleRate,
                  Int(format.channelCount) == spec.channels,
                  file.length > 0
            else { throw GenerationError.wrongFormat(name: spec.name, expected: expected, actual: actual) }
        }

        let hollow = root.appendingPathComponent(hollowClipName)
        let hollowFile: AVAudioFile
        do { hollowFile = try AVAudioFile(forReading: hollow) }
        catch { throw GenerationError.unreadable(name: hollowClipName, underlying: "\(error)") }
        let promised = Double(hollowFile.length) / hollowFile.processingFormat.sampleRate
        guard promised > 60 else {
            throw GenerationError.wrongFormat(
                name: hollowClipName,
                expected: "a container promising far more audio than it holds",
                actual: String(format: "%.2f s", promised)
            )
        }
        return root
    }

    // MARK: - Synthesis

    /// A steady two-tone (one frequency per channel) 16-bit PCM WAVE file. A
    /// continuous tone rather than silence, so "the render clock advanced" is
    /// backed by something a listener would actually hear, and so the FLAC/ALAC
    /// encoders have real signal to compress.
    private static func writeTone(to url: URL, sampleRate: Double, channels: Int) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(sampleRate * clipSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw GenerationError.unreadable(name: url.lastPathComponent, underlying: "no PCM buffer")
        }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            let hertz = 330.0 + 110.0 * Double(channel)
            for frame in 0..<Int(frames) {
                samples[frame] = Float(0.25 * sin(2 * .pi * hertz * Double(frame) / sampleRate))
            }
        }
        try file.write(from: buffer)
    }

    private static let encoderPath = "/usr/bin/afconvert"

    private static func encode(_ source: URL, to destination: URL, as spec: Spec) throws {
        guard FileManager.default.isExecutableFile(atPath: encoderPath) else {
            throw GenerationError.encoderMissing(encoderPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: encoderPath)
        process.arguments = ["-f", spec.fileFormat, "-d", spec.dataFormat,
                             source.path, destination.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GenerationError.encodeFailed(
                name: spec.name, status: process.terminationStatus, output: output
            )
        }
    }

    // MARK: - The hollow container

    /// Write a CAF whose `desc` chunk describes `claimedSeconds` of PCM and
    /// whose `data` chunk declares that many bytes — then end the file. The
    /// result opens, reports the promised duration, and yields no frames.
    ///
    /// CAF is used because its layout makes the trick honest and tiny: a fixed
    /// 8-byte header, a 32-byte `desc`, and a `data` chunk whose 64-bit declared
    /// size is what `AVAudioFile` divides by the frame size to get its length.
    private static func writeHollowCAF(
        to url: URL, sampleRate: Double, channels: Int, claimedSeconds: Double
    ) throws {
        func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
            withUnsafeBytes(of: value.bigEndian) { Data($0) }
        }
        func ascii(_ s: String) -> Data { Data(s.utf8) }

        let bytesPerFrame = UInt32(channels * 2)
        let claimedFrames = Int64(claimedSeconds * sampleRate)

        var file = Data()
        file += ascii("caff")
        file += bigEndian(UInt16(1))                       // version
        file += bigEndian(UInt16(0))                       // flags

        file += ascii("desc")
        file += bigEndian(Int64(32))                       // chunk size
        file += bigEndian(sampleRate.bitPattern)           // mSampleRate (Float64, BE)
        file += ascii("lpcm")                              // mFormatID
        file += bigEndian(UInt32(2))                       // mFormatFlags: signed integer
        file += bigEndian(bytesPerFrame)                   // mBytesPerPacket
        file += bigEndian(UInt32(1))                       // mFramesPerPacket
        file += bigEndian(UInt32(channels))                // mChannelsPerFrame
        file += bigEndian(UInt32(16))                      // mBitsPerChannel

        file += ascii("data")
        // The lie: the declared size covers `claimedFrames` of audio (plus the
        // 4-byte edit count), and then the file simply stops.
        file += bigEndian(Int64(4) + claimedFrames * Int64(bytesPerFrame))
        file += bigEndian(UInt32(0))                       // mEditCount

        try file.write(to: url)
    }
}
