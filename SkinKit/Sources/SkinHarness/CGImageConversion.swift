import CoreGraphics
import Foundation
import SkinKit

// MARK: - DecodedBitmap -> CGImage

/// Bridges a platform-neutral `DecodedBitmap` into a `CGImage` for drawing.
///
/// `DecodedBitmap` is RGBA8, row-major, top-left origin, straight alpha. We
/// describe the buffer to CoreGraphics with the matching byte order and an
/// sRGB color space so the colors render faithfully.
enum CGImageConversion {

    /// Pixel layout for the decoded buffer.
    ///
    /// The buffer bytes are laid out R, G, B, A per pixel. We pair byte order
    /// `.byteOrder32Big` with `CGImageAlphaInfo.last` so CoreGraphics reads the
    /// first byte as red and the trailing byte as alpha. The source data is
    /// fully opaque straight RGBA, so treating the last channel as (opaque)
    /// alpha reproduces the original colors without premultiplication artifacts.
    static let bitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.last.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    )

    /// Builds a `CGImage` from a decoded RGBA8 bitmap, or `nil` if the buffer
    /// size does not match the declared dimensions.
    static func makeImage(from bitmap: DecodedBitmap) -> CGImage? {
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
