import Foundation
import XCTest
import SkinKit
@testable import SkinKitImageIO

/// Tests for the ImageIO-backed bitmap decoder. Each test maps to one
/// acceptance criterion; BMP inputs are assembled in-memory via
/// `BMPFixtureBuilder` so no real image files are required.
final class ImageIOBitmapDecoderTests: XCTestCase {

    private let decoder = ImageIOBitmapDecoder()

    // MARK: - Criterion 3: 24-bit BMP yields correct dimensions

    func test24BitBMPReturnsCorrectDimensions() {
        let red: (r: UInt8, g: UInt8, b: UInt8) = (255, 0, 0)
        let rows = Array(repeating: Array(repeating: red, count: 4), count: 3)
        let data = BMPFixtureBuilder.bmp24(width: 4, height: 3, rows: rows)

        let decoded = decoder.decode(data)

        XCTAssertEqual(decoded?.width, 4)
        XCTAssertEqual(decoded?.height, 3)
        XCTAssertEqual(decoded?.pixels.count, 4 * 3 * 4)
    }

    // MARK: - Criterion 4: pixel correctness, top-left origin, RGBA order

    func test24BitBMPPixelsAreTopLeftOriginRGBA() throws {
        // Distinct corner colors so origin and channel order are both pinned.
        let topLeft: (r: UInt8, g: UInt8, b: UInt8) = (255, 0, 0)       // red
        let topRight: (r: UInt8, g: UInt8, b: UInt8) = (0, 255, 0)      // green
        let bottomLeft: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 255)    // blue
        let bottomRight: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 0) // yellow

        let rows = [
            [topLeft, topRight],       // top row (top-down order)
            [bottomLeft, bottomRight], // bottom row
        ]
        let data = BMPFixtureBuilder.bmp24(width: 2, height: 2, rows: rows)

        let decoded = try XCTUnwrap(decoder.decode(data))
        let pixels = decoded.pixels

        // Row-major, top-left origin. Pixel (x, y) starts at (y * width + x) * 4.
        XCTAssertEqual(pixel(pixels, x: 0, y: 0, width: 2), [255, 0, 0, 255])   // top-left red
        XCTAssertEqual(pixel(pixels, x: 1, y: 0, width: 2), [0, 255, 0, 255])   // top-right green
        XCTAssertEqual(pixel(pixels, x: 0, y: 1, width: 2), [0, 0, 255, 255])   // bottom-left blue
        XCTAssertEqual(pixel(pixels, x: 1, y: 1, width: 2), [255, 255, 0, 255]) // bottom-right yellow
    }

    // MARK: - Criterion 5: 8-bit palette BMP yields dimensions + sampled pixel

    func test8BitPaletteBMPReturnsDimensionsAndSampledPixel() throws {
        let palette: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (10, 20, 30),     // index 0
            (200, 100, 50),   // index 1
        ]
        let rows: [[UInt8]] = [
            [0, 1],  // top row: index 0, index 1
            [1, 0],  // bottom row
        ]
        let data = BMPFixtureBuilder.bmp8(width: 2, height: 2, palette: palette, rows: rows)

        let decoded = try XCTUnwrap(decoder.decode(data))

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        // Top-left is palette index 0 -> (10, 20, 30) opaque.
        XCTAssertEqual(pixel(decoded.pixels, x: 0, y: 0, width: 2), [10, 20, 30, 255])
        // Top-right is palette index 1 -> (200, 100, 50) opaque.
        XCTAssertEqual(pixel(decoded.pixels, x: 1, y: 0, width: 2), [200, 100, 50, 255])
    }

    // MARK: - Criterion 6: garbage data returns nil

    func testGarbageDataReturnsNil() {
        XCTAssertNil(decoder.decode(Data("not an image at all".utf8)))
        XCTAssertNil(decoder.decode(Data()))
        XCTAssertNil(decoder.decode(Data([0x42, 0x4D, 0x00, 0x01]))) // 'BM' prefix but truncated
    }

    // MARK: - Helpers

    private func pixel(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> [UInt8] {
        let base = (y * width + x) * 4
        guard base + 4 <= pixels.count else { return [] }
        return Array(pixels[base..<base + 4])
    }
}
