import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Nearest-neighbor scaling

/// Errors that can arise while rendering or exporting a skin image.
enum RenderError: Error, CustomStringConvertible {
    case contextCreationFailed
    case pngDestinationFailed
    case pngWriteFailed

    var description: String {
        switch self {
        case .contextCreationFailed:
            return "Could not create a graphics context for the scaled image."
        case .pngDestinationFailed:
            return "Could not create a PNG destination for the output path."
        case .pngWriteFailed:
            return "Could not write the PNG to disk."
        }
    }
}

/// Renders `image` into a freshly allocated bitmap scaled by `scale`, using
/// nearest-neighbor interpolation so the pixels stay crisp at integer zoom.
///
/// Returns the scaled `CGImage` and its pixel dimensions.
func scaledImage(
    _ image: CGImage,
    scale: Int
) throws -> (image: CGImage, width: Int, height: Int) {
    let outWidth = image.width * scale
    let outHeight = image.height * scale

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: outWidth,
              height: outHeight,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageConversionPNGAlpha
          ) else {
        throw RenderError.contextCreationFailed
    }

    // Nearest-neighbor: a core skin-rendering requirement so integer scaling
    // never blurs the pixel art.
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

    guard let scaled = context.makeImage() else {
        throw RenderError.contextCreationFailed
    }
    return (scaled, outWidth, outHeight)
}

/// Bitmap info used for the offscreen PNG context: premultiplied-last RGBA over
/// sRGB, which is what CoreGraphics bitmap contexts support for 8-bit RGBA.
private let CGImageConversionPNGAlpha = CGImageAlphaInfo.premultipliedLast.rawValue
    | CGBitmapInfo.byteOrder32Big.rawValue

// MARK: - PNG export (headless)

/// Writes `image` to `url` as a PNG. Runs fully offscreen with no run loop.
func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw RenderError.pngDestinationFailed
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw RenderError.pngWriteFailed
    }
}

// MARK: - Window view

/// A view that draws a `CGImage` with nearest-neighbor scaling so the skin's
/// pixel art stays crisp when the window is sized to an integer multiple.
final class SkinImageView: NSView {
    private let image: CGImage

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }
}
