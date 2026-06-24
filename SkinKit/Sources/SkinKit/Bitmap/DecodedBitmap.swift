import Foundation

// MARK: - DecodedBitmap

/// A fully decoded raster image in a single, platform-neutral pixel layout.
///
/// Pixels are RGBA8, row-major, with the origin at the **top-left** corner. The
/// buffer is exactly `width * height * 4` bytes and uses **straight**
/// (non-premultiplied) alpha. Keeping this type free of any image framework
/// lets the core module describe decoded images without depending on platform
/// graphics libraries; concrete decoders live in separate modules.
public struct DecodedBitmap: Equatable {
    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// RGBA8 pixels, row-major, top-left origin, straight alpha. Exactly
    /// `width * height * 4` bytes.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}
