import Foundation

// MARK: - ZipError

/// The only fatal failure mode for opening an archive. Per-entry problems are
/// reported by `ZipArchive.extract(_:)` returning `nil`, never by throwing.
public enum ZipError: Error, Sendable {
    /// No End-Of-Central-Directory record could be located in the data.
    case notAZipArchive
}

// MARK: - ZipEntry

/// One file recorded in the archive's central directory.
public struct ZipEntry: Sendable {
    /// The entry path exactly as stored in the archive.
    public let path: String
    /// Number of bytes the file occupies in compressed form.
    public let compressedSize: Int
    /// Number of bytes the file occupies once decompressed.
    public let uncompressedSize: Int
    /// `true` only when the compression method is stored (0) or deflate (8).
    public let isSupported: Bool
}
