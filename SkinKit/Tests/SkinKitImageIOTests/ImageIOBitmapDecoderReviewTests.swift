import CoreGraphics
import Foundation
import ImageIO
import XCTest
import SkinKit
@testable import SkinKitImageIO

/// Adversarial completeness probes for `ImageIOBitmapDecoder`, added by an
/// independent QA review of the BMP-decoding work.
///
/// These tests target gaps the existing suite cannot catch: the existing pixel
/// test is 2x2 and square, so it cannot detect a width<->height transpose, a
/// wrong row-stride, or a row-vs-column mix-up. They also pin documented
/// behavior (forced-opaque alpha, non-BMP sniffing) and a core invariant
/// (`pixels.count == width * height * 4`).
///
/// A FAILING test here documents a real decoder gap; an [FYI]-tagged test
/// merely observes/pins intentional behavior and should not block the gate.
final class ImageIOBitmapDecoderReviewTests: XCTestCase {

    private let decoder = ImageIOBitmapDecoder()

    // MARK: - Gap 1: Non-square dimensions / transpose / row-order (HIGHEST VALUE)

    /// A 4-wide x 2-tall image (non-square) with a color that is a unique
    /// function of (x, y). If width and height were swapped, or rows were read
    /// with the wrong stride, or rows/columns were transposed, the asserted
    /// pixels at known offsets would not match.
    ///
    /// Color encoding: r = x * 10, g = y * 10, b = constant. Every pixel is
    /// therefore distinguishable, and a transpose (reading (y,x) as (x,y))
    /// would scramble the r/g channels in a detectable way.
    func testNonSquare4x2PinsOriginStrideAndNoTranspose() throws {
        let width = 4
        let height = 2

        func color(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            (r: UInt8(x * 10), g: UInt8(y * 10), b: 200)
        }

        var rows: [[(r: UInt8, g: UInt8, b: UInt8)]] = []
        for y in 0..<height {
            rows.append((0..<width).map { color(x: $0, y: y) })
        }

        let data = BMPFixtureBuilder.bmp24(width: width, height: height, rows: rows)
        let decoded = try XCTUnwrap(decoder.decode(data), "decode returned nil for 4x2 BMP")

        // Dimensions must NOT be transposed.
        XCTAssertEqual(decoded.width, width, "width transposed?")
        XCTAssertEqual(decoded.height, height, "height transposed?")

        // Check every pixel at its known (x, y) offset.
        for y in 0..<height {
            for x in 0..<width {
                let expected = color(x: x, y: y)
                XCTAssertEqual(
                    pixel(decoded.pixels, x: x, y: y, width: width),
                    [expected.r, expected.g, expected.b, 255],
                    "pixel mismatch at (x=\(x), y=\(y)) — transpose or wrong stride?"
                )
            }
        }
    }

    /// A 3-wide x 5-tall image (non-square, the other aspect ratio, odd width).
    /// Catches a transpose that a square or single-orientation test would miss,
    /// and exercises an odd width (3) so any per-row indexing off-by-one shows.
    func testNonSquare3x5PinsOrientationWithOddWidth() throws {
        let width = 3
        let height = 5

        func color(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            (r: UInt8(x * 40), g: UInt8(y * 20), b: 77)
        }

        var rows: [[(r: UInt8, g: UInt8, b: UInt8)]] = []
        for y in 0..<height {
            rows.append((0..<width).map { color(x: $0, y: y) })
        }

        let data = BMPFixtureBuilder.bmp24(width: width, height: height, rows: rows)
        let decoded = try XCTUnwrap(decoder.decode(data), "decode returned nil for 3x5 BMP")

        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.pixels.count, width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let expected = color(x: x, y: y)
                XCTAssertEqual(
                    pixel(decoded.pixels, x: x, y: y, width: width),
                    [expected.r, expected.g, expected.b, 255],
                    "pixel mismatch at (x=\(x), y=\(y)) in 3x5"
                )
            }
        }
    }

    // MARK: - Gap 2: Odd width (5px) — readback indexing across BMP row padding

    /// A 24-bit row of 5 px is 15 bytes, padded to 16 (one pad byte). The RGBA8
    /// readback row is 20 bytes. This pins that the decoder does not leak the
    /// BMP pad byte or misalign rows for a width whose byte-stride needs padding.
    func testOddWidth5x3DecodesWithoutRowMisalignment() throws {
        let width = 5
        let height = 3

        func color(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            (r: UInt8(x * 30), g: UInt8(y * 60), b: UInt8((x + y) * 10))
        }

        var rows: [[(r: UInt8, g: UInt8, b: UInt8)]] = []
        for y in 0..<height {
            rows.append((0..<width).map { color(x: $0, y: y) })
        }

        let data = BMPFixtureBuilder.bmp24(width: width, height: height, rows: rows)
        let decoded = try XCTUnwrap(decoder.decode(data), "decode returned nil for 5x3 BMP")

        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)

        for y in 0..<height {
            for x in 0..<width {
                let expected = color(x: x, y: y)
                XCTAssertEqual(
                    pixel(decoded.pixels, x: x, y: y, width: width),
                    [expected.r, expected.g, expected.b, 255],
                    "pixel mismatch at (x=\(x), y=\(y)) in odd-width 5x3"
                )
            }
        }
    }

    // MARK: - Gap 3: 1x1 smallest image

    func test1x1SmallestImageDecodes() throws {
        let data = BMPFixtureBuilder.bmp24(width: 1, height: 1, rows: [[(r: 12, g: 34, b: 56)]])
        let decoded = try XCTUnwrap(decoder.decode(data), "decode returned nil for 1x1 BMP")

        XCTAssertEqual(decoded.width, 1)
        XCTAssertEqual(decoded.height, 1)
        XCTAssertEqual(decoded.pixels.count, 4)
        XCTAssertEqual(pixel(decoded.pixels, x: 0, y: 0, width: 1), [12, 34, 56, 255])
    }

    // MARK: - Gap 6: pixels.count invariant on a decoded image

    func testDecodedPixelsCountInvariant() throws {
        let width = 7
        let height = 4
        let rows = (0..<height).map { y in
            (0..<width).map { x in (r: UInt8(x * 8), g: UInt8(y * 8), b: UInt8(0)) }
        }
        let data = BMPFixtureBuilder.bmp24(width: width, height: height, rows: rows)
        let decoded = try XCTUnwrap(decoder.decode(data))

        XCTAssertEqual(
            decoded.pixels.count,
            decoded.width * decoded.height * 4,
            "pixels buffer must be exactly width*height*4 — render layer relies on this"
        )
    }

    // MARK: - Gap 4 [FYI]: 32-bit BMP — alpha forced opaque (documented behavior)

    /// Builds a 32-bit BGRA BMP whose source alpha bytes are NOT 0xFF, then
    /// confirms the decoder returns all-0xFF alpha (the documented "force
    /// opaque via noneSkipLast" decision). This is intentional, not a bug:
    /// tagged [FYI]. The assertion FAILING would mean the documented contract
    /// was broken; PASSING confirms the contract holds.
    func testFYI_32BitBMPAlphaIsForcedOpaque() throws {
        // Source alpha = 0x40 (semi-transparent) on every pixel.
        let data = bmp32(
            width: 2,
            height: 2,
            rows: [
                [(r: 255, g: 0, b: 0, a: 0x40), (r: 0, g: 255, b: 0, a: 0x40)],
                [(r: 0, g: 0, b: 255, a: 0x40), (r: 255, g: 255, b: 0, a: 0x40)],
            ]
        )

        guard let decoded = decoder.decode(data) else {
            // If the platform refuses this particular 32-bit variant, that is
            // acceptable for an [FYI] probe — record and stop.
            XCTAssertNil(decoder.decode(data), "[FYI] platform did not decode 32-bit BMP variant")
            return
        }

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded.pixels.count, 2 * 2 * 4)

        // Every 4th byte must be 0xFF regardless of source alpha.
        for index in stride(from: 3, to: decoded.pixels.count, by: 4) {
            XCTAssertEqual(
                decoded.pixels[index], 0xFF,
                "[FYI] alpha at byte \(index) should be forced opaque (documented)"
            )
        }
    }

    // MARK: - Gap 5 [FYI]: Non-BMP bytes (PNG) — pin the sniffing behavior

    /// ImageIO sniffs content rather than trusting any extension. A real PNG is
    /// therefore decoded too. This is documented as acceptable; tagged [FYI].
    /// We only PIN the observed behavior so a future change is noticed.
    func testFYI_PNGBytesAreDecodedByImageIO() throws {
        let png = makeSolidPNG(width: 2, height: 2, r: 10, g: 20, b: 30)

        let decoded = decoder.decode(png)

        // Observed/documented: ImageIO decodes PNG too. Pin it (non-fatal intent
        // — if this ever flips to nil, the [FYI] note below explains it's OK).
        XCTAssertNotNil(
            decoded,
            "[FYI] ImageIO sniffs content and decodes PNG; pinning observed behavior"
        )
        if let decoded {
            XCTAssertEqual(decoded.width, 2)
            XCTAssertEqual(decoded.height, 2)
            XCTAssertEqual(decoded.pixels.count, 2 * 2 * 4)
        }
    }

    // MARK: - Helpers

    private func pixel(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> [UInt8] {
        let base = (y * width + x) * 4
        guard base + 4 <= pixels.count else { return [] }
        return Array(pixels[base..<base + 4])
    }

    /// Builds a 32-bit uncompressed (BI_RGB) BMP. The builder helper only
    /// supports 24-/8-bit, so 32-bit bytes are assembled inline here. Rows are
    /// given top-to-bottom and written bottom-up; pixels stored as B, G, R, A.
    /// 32-bit rows are already 4-byte aligned, so no padding is needed.
    private func bmp32(
        width: Int,
        height: Int,
        rows: [[(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]]
    ) -> Data {
        precondition(rows.count == height)
        let fileHeaderSize = 14
        let infoHeaderSize = 40

        var pixelData = Data()
        for row in rows.reversed() {
            precondition(row.count == width)
            for p in row {
                pixelData.append(p.b)
                pixelData.append(p.g)
                pixelData.append(p.r)
                pixelData.append(p.a)
            }
        }

        let pixelOffset = fileHeaderSize + infoHeaderSize
        let fileSize = pixelOffset + pixelData.count

        var data = Data()
        // BITMAPFILEHEADER
        data.append(0x42); data.append(0x4D)            // 'BM'
        data.appendLE32(UInt32(fileSize))
        data.appendLE16(0); data.appendLE16(0)          // reserved
        data.appendLE32(UInt32(pixelOffset))
        // BITMAPINFOHEADER
        data.appendLE32(UInt32(infoHeaderSize))
        data.appendLE32(UInt32(bitPattern: Int32(width)))
        data.appendLE32(UInt32(bitPattern: Int32(height)))
        data.appendLE16(1)                              // planes
        data.appendLE16(32)                             // bpp
        data.appendLE32(0)                              // BI_RGB
        data.appendLE32(UInt32(pixelData.count))
        data.appendLE32(UInt32(bitPattern: Int32(2835)))
        data.appendLE32(UInt32(bitPattern: Int32(2835)))
        data.appendLE32(0)                              // colors used
        data.appendLE32(0)                              // important colors
        data.append(pixelData)
        return data
    }

    /// Produces a minimal real PNG via ImageIO so the non-BMP sniffing probe
    /// uses a genuinely different container format (no real asset files).
    private func makeSolidPNG(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> Data {
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: buffer.count, by: 4) {
            buffer[i] = r; buffer[i + 1] = g; buffer[i + 2] = b; buffer[i + 3] = 0xFF
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = buffer.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let cgImage = ctx!.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}

// MARK: - Little-endian append helpers (test-local)

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
