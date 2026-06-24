import Foundation

// MARK: - BitmapDecoding

/// Decodes encoded image bytes into a `DecodedBitmap`.
///
/// The protocol is platform-neutral so the core module can depend on the
/// abstraction while concrete, framework-backed implementations live elsewhere
/// (and can be swapped or stubbed in tests).
public protocol BitmapDecoding {
    /// Decode image bytes (e.g. BMP) into RGBA8 pixels. Returns `nil` if the
    /// data cannot be decoded.
    func decode(_ data: Data) -> DecodedBitmap?
}
