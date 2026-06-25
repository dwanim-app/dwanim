import CoreGraphics
import Foundation
import SkinKit

// MARK: - DecodedBitmap -> CGImage

/// Bridges a platform-neutral `DecodedBitmap` into a `CGImage` for drawing.
///
/// `DecodedBitmap` is RGBA8, row-major, top-left origin, straight alpha. We
/// describe the buffer to CoreGraphics with the matching byte order and an
/// sRGB color space so the colors render faithfully.
///
/// Lifted unchanged from the SkinHarness shell into the reusable AppKit tier so
/// both the harness and the upcoming app target can bridge composed bitmaps.
public enum CGImageConversion {

    /// Pixel layout for the decoded buffer.
    ///
    /// The buffer bytes are laid out R, G, B, A per pixel. We pair byte order
    /// `.byteOrder32Big` with `CGImageAlphaInfo.premultipliedLast` so
    /// CoreGraphics reads the first byte as red and the trailing byte as alpha,
    /// and HONORS that alpha as transparency.
    ///
    /// A fully-opaque bitmap (alpha 0xFF everywhere) is unaffected by
    /// premultiplication — `rgb * 1.0 == rgb` — so the common unmasked case
    /// renders identically to a straight-alpha bridge. When a shape mask has
    /// zeroed the alpha of out-of-region pixels, premultiplication makes those
    /// pixels fully transparent, which is exactly what a shaped window / alpha
    /// PNG needs. (The DecodedBitmap carries straight alpha; for the only two
    /// alpha values we ever produce here — 0xFF and 0x00 — straight and
    /// premultiplied representations coincide, so no precision is lost.)
    public static let bitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    )

    /// Builds a `CGImage` from a decoded RGBA8 bitmap, or `nil` if the buffer
    /// size does not match the declared dimensions.
    public static func makeImage(from bitmap: DecodedBitmap) -> CGImage? {
        let width = bitmap.width
        let height = bitmap.height
        let bytesPerRow = width * 4

        guard width > 0, height > 0,
              bitmap.pixels.count == bytesPerRow * height else {
            return nil
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bitmap.pixels) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
