import Foundation
import XCTest
@testable import SkinKit

/// Tests for the platform-neutral bitmap value type and decoding protocol that
/// live in the core module. The core must remain free of any image framework,
/// so these tests only exercise plain value semantics and protocol usability.
final class DecodedBitmapTests: XCTestCase {

    // MARK: - Criterion 1: stores width/height/pixels

    func testStoresWidthHeightAndPixels() {
        let pixels: [UInt8] = [1, 2, 3, 4]
        let bitmap = DecodedBitmap(width: 1, height: 1, pixels: pixels)

        XCTAssertEqual(bitmap.width, 1)
        XCTAssertEqual(bitmap.height, 1)
        XCTAssertEqual(bitmap.pixels, pixels)
    }

    // MARK: - Criterion 1: Equatable conformance

    func testEqualBitmapsCompareEqual() {
        let lhs = DecodedBitmap(width: 2, height: 1, pixels: [0, 0, 0, 255, 255, 255, 255, 255])
        let rhs = DecodedBitmap(width: 2, height: 1, pixels: [0, 0, 0, 255, 255, 255, 255, 255])

        XCTAssertEqual(lhs, rhs)
    }

    func testDifferingBitmapsCompareUnequal() {
        let base = DecodedBitmap(width: 1, height: 1, pixels: [10, 20, 30, 40])

        XCTAssertNotEqual(base, DecodedBitmap(width: 2, height: 1, pixels: [10, 20, 30, 40]))
        XCTAssertNotEqual(base, DecodedBitmap(width: 1, height: 2, pixels: [10, 20, 30, 40]))
        XCTAssertNotEqual(base, DecodedBitmap(width: 1, height: 1, pixels: [10, 20, 30, 99]))
    }

    // MARK: - Criterion 2: protocol is usable / injectable via a stub

    func testStubDecoderConformsAndIsInjectable() {
        let decoder: BitmapDecoding = StubBitmapDecoder()
        let decoded = decoder.decode(Data([0xFF]))

        XCTAssertEqual(decoded, DecodedBitmap(width: 1, height: 1, pixels: [255, 0, 0, 255]))
    }
}

// MARK: - StubBitmapDecoder

/// A trivial in-test decoder proving `BitmapDecoding` can be implemented and
/// injected without any image framework. It ignores its input and returns a
/// fixed opaque-red 1x1 bitmap.
private struct StubBitmapDecoder: BitmapDecoding {
    func decode(_ data: Data) -> DecodedBitmap? {
        DecodedBitmap(width: 1, height: 1, pixels: [255, 0, 0, 255])
    }
}
