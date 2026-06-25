import Foundation

// MARK: - SineWAVFactory

/// Builds a self-contained PCM WAV file in memory and writes it to a temp URL.
///
/// The bytes are assembled by hand — a canonical 44-byte RIFF/WAVE header
/// followed by interleaved 16-bit little-endian PCM samples of a sine tone — so
/// the tests never depend on any external or copyrighted audio asset. The file
/// is deterministic given its parameters, which keeps the offline-render
/// assertions stable.
enum SineWAVFactory {

    // MARK: - Public API

    /// Writes a sine-tone WAV to a unique temp file and returns its URL.
    ///
    /// - Parameters:
    ///   - duration: Length in seconds.
    ///   - sampleRate: Frames per second.
    ///   - channels: 1 (mono) or 2 (stereo); stereo duplicates the tone.
    ///   - frequency: Tone frequency in Hz.
    ///   - amplitude: Peak amplitude in `0...1` (scaled to 16-bit range).
    static func write(
        duration: Double = 1.0,
        sampleRate: Double = 44_100,
        channels: Int = 1,
        frequency: Double = 440,
        amplitude: Double = 0.5
    ) throws -> URL {
        let data = makeWAVData(
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            frequency: frequency,
            amplitude: amplitude
        )
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try data.write(to: url)
        return url
    }

    /// Writes a **multi-tone** (broadband) WAV: the sum of equal-amplitude sine
    /// tones at each of `frequencies`, normalized so the summed peak stays in
    /// range. Returns its temp URL.
    ///
    /// Used by the EQ DSP-proof: placing one tone at each equalizer band centre
    /// gives a signal with energy spread across the spectrum, so boosting one
    /// band must measurably raise that band's tone relative to a flat render.
    static func writeMultiTone(
        frequencies: [Double],
        duration: Double = 1.0,
        sampleRate: Double = 44_100,
        channels: Int = 1,
        amplitude: Double = 0.8
    ) throws -> URL {
        let data = makeMultiToneWAVData(
            frequencies: frequencies,
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            amplitude: amplitude
        )
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try data.write(to: url)
        return url
    }

    /// The exact number of sample frames a file of these parameters contains.
    static func frameCount(duration: Double, sampleRate: Double) -> Int {
        Int((duration * sampleRate).rounded())
    }

    // MARK: - Byte assembly

    private static func makeWAVData(
        duration: Double,
        sampleRate: Double,
        channels: Int,
        frequency: Double,
        amplitude: Double
    ) -> Data {
        let frames = frameCount(duration: duration, sampleRate: sampleRate)
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = channels * bytesPerSample
        let byteRate = Int(sampleRate) * blockAlign
        let dataSize = frames * blockAlign

        var data = Data()
        appendRIFFHeader(to: &data, dataSize: dataSize)
        appendFormatChunk(
            to: &data,
            channels: channels,
            sampleRate: Int(sampleRate),
            byteRate: byteRate,
            blockAlign: blockAlign,
            bitsPerSample: bitsPerSample
        )
        appendDataChunk(
            to: &data,
            dataSize: dataSize,
            frames: frames,
            channels: channels,
            sampleRate: sampleRate,
            frequency: frequency,
            amplitude: amplitude
        )
        return data
    }

    private static func makeMultiToneWAVData(
        frequencies: [Double],
        duration: Double,
        sampleRate: Double,
        channels: Int,
        amplitude: Double
    ) -> Data {
        let frames = frameCount(duration: duration, sampleRate: sampleRate)
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = channels * bytesPerSample
        let byteRate = Int(sampleRate) * blockAlign
        let dataSize = frames * blockAlign

        var data = Data()
        appendRIFFHeader(to: &data, dataSize: dataSize)
        appendFormatChunk(
            to: &data,
            channels: channels,
            sampleRate: Int(sampleRate),
            byteRate: byteRate,
            blockAlign: blockAlign,
            bitsPerSample: bitsPerSample
        )

        data.append(ascii: "data")
        data.appendUInt32LE(UInt32(dataSize))

        // Normalize so the SUM of all tones cannot clip: divide by the tone
        // count, then scale by the requested peak amplitude.
        let toneScale = frequencies.isEmpty ? 1.0 : 1.0 / Double(frequencies.count)
        let peak = amplitude * toneScale * Double(Int16.max)
        for frame in 0..<frames {
            var value = 0.0
            for frequency in frequencies {
                let theta = 2.0 * Double.pi * frequency * Double(frame) / sampleRate
                value += sin(theta)
            }
            let sample = Int16((value * peak).rounded())
            for _ in 0..<channels {
                data.appendInt16LE(sample)
            }
        }
        return data
    }

    private static func appendRIFFHeader(to data: inout Data, dataSize: Int) {
        data.append(ascii: "RIFF")
        data.appendUInt32LE(UInt32(36 + dataSize))
        data.append(ascii: "WAVE")
    }

    private static func appendFormatChunk(
        to data: inout Data,
        channels: Int,
        sampleRate: Int,
        byteRate: Int,
        blockAlign: Int,
        bitsPerSample: Int
    ) {
        data.append(ascii: "fmt ")
        data.appendUInt32LE(16)            // PCM chunk size
        data.appendUInt16LE(1)             // PCM format tag
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
    }

    private static func appendDataChunk(
        to data: inout Data,
        dataSize: Int,
        frames: Int,
        channels: Int,
        sampleRate: Double,
        frequency: Double,
        amplitude: Double
    ) {
        data.append(ascii: "data")
        data.appendUInt32LE(UInt32(dataSize))

        let peak = amplitude * Double(Int16.max)
        for frame in 0..<frames {
            let theta = 2.0 * Double.pi * frequency * Double(frame) / sampleRate
            let sample = Int16((sin(theta) * peak).rounded())
            for _ in 0..<channels {
                data.appendInt16LE(sample)
            }
        }
    }
}

// MARK: - Data little-endian helpers

private extension Data {
    mutating func append(ascii string: String) {
        append(contentsOf: Array(string.utf8))
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendInt16LE(_ value: Int16) {
        appendUInt16LE(UInt16(bitPattern: value))
    }
}
