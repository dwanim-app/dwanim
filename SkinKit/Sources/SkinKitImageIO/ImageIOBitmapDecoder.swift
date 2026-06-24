import CoreGraphics
import Foundation
import ImageIO
import SkinKit

// MARK: - ImageIOBitmapDecoder

/// A `BitmapDecoding` implementation backed by the platform's ImageIO and
/// CoreGraphics frameworks. It delegates format parsing (including the various
/// BMP variants the platform decodes natively) to `CGImageSource`, then draws
/// the resulting image into a known canonical buffer.
///
/// The canonical buffer is **RGBA8, top-left origin, straight (non-premultiplied)
/// alpha**, matching `DecodedBitmap`'s contract:
/// - Pixel format `kCGImageAlphaNoneSkipLast` (RGBX) over the sRGB color space,
///   so each pixel is laid out as R, G, B, then an unused byte we force to 0xFF.
///   `NoneSkipLast` keeps color channels straight (CoreGraphics never
///   premultiplies when there is no meaningful alpha), which is exactly the
///   "straight RGBA" we want for fully opaque source images such as BMP.
/// - A bitmap context's first buffer row is the top of the image, so a straight
///   draw (no coordinate flip) already lands the image top-left-first.
public struct ImageIOBitmapDecoder: BitmapDecoding {

    public init() {}

    // MARK: - Decoding

    public func decode(_ data: Data) -> DecodedBitmap? {
        guard let image = makeImage(from: data) else { return nil }
        return render(image)
    }

    // MARK: - Image source

    private func makeImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Rendering to canonical RGBA8

    private func render(_ image: CGImage) -> DecodedBitmap? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        // RGBX, straight alpha. The trailing byte is unused ("skip") rather than
        // a premultiplying alpha channel, so the R, G, B values stay straight.
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            // A CoreGraphics bitmap context lays the first buffer row out as the
            // top of the image, so a straight draw (no coordinate flip) already
            // yields a top-left-origin buffer.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else { return nil }

        // `NoneSkipLast` leaves the 4th byte undefined; force a fully opaque
        // alpha so the buffer is valid straight RGBA8.
        for index in stride(from: 3, to: buffer.count, by: 4) {
            buffer[index] = 0xFF
        }

        return DecodedBitmap(width: width, height: height, pixels: buffer)
    }
}
