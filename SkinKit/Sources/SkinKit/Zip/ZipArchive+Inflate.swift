import Compression
import Foundation

// MARK: - DEFLATE decompression

extension ZipArchive {

    /// Inflates a raw DEFLATE stream (no zlib/gzip wrapper) into at most
    /// `expectedSize` bytes. Returns `nil` on any decoding error. A truncated or
    /// corrupt stream that decodes to the wrong number of bytes is still
    /// rejected by the size and CRC checks in `extract(_:)`.
    static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        // A zero-length payload has no meaningful stream to decode.
        if expectedSize == 0 {
            return Data()
        }
        guard !input.isEmpty else { return nil }

        var output = Data(count: expectedSize)
        let produced = output.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard produced > 0 else { return nil }
        if produced != expectedSize {
            output = output.prefix(produced)
        }
        return output
    }
}
