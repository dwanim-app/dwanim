import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// Exercises the pure RGBA8 main-window compositor on synthetic skins built
/// entirely in-memory (no real `.wsz` files, no graphics framework). Each test
/// asserts directly on the returned `DecodedBitmap.pixels`, proving the
/// compositor's placement, draw order, fault tolerance, clipping, and origin
/// behavior without any platform image bridge.
final class MainWindowComposerTests: XCTestCase {

    // MARK: - Helpers

    /// A solid-color RGBA8 bitmap of the given size, every pixel set to `color`.
    private func solidBitmap(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8, UInt8)
    ) -> DecodedBitmap {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = color.3
        }
        return DecodedBitmap(width: width, height: height, pixels: pixels)
    }

    /// The RGBA tuple at `(x, y)` in a bitmap, read straight from the buffer.
    private func pixel(_ bitmap: DecodedBitmap, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * bitmap.width + x) * 4
        return (
            bitmap.pixels[index],
            bitmap.pixels[index + 1],
            bitmap.pixels[index + 2],
            bitmap.pixels[index + 3]
        )
    }

    /// Builds a `Skin` whose only sprite sheet content is the given
    /// sheet → name → bitmap nesting.
    private func makeSkin(sprites: [String: [String: DecodedBitmap]]) -> Skin {
        Skin(sprites: sprites, visColors: [], playlist: nil, region: nil)
    }

    private let opaqueWhite: (UInt8, UInt8, UInt8, UInt8) = (255, 255, 255, 255)

    // MARK: - 1. Placement (non-flipped origin)

    /// Background of the standard size plus every layout element rendered as a
    /// distinct solid color at its nominal size. The composed pixel at each
    /// element's top-left `(x, y)` must equal that element's color — proving the
    /// sprite lands at its layout position with a top-left (non-flipped) origin.
    func testEveryElementLandsAtItsLayoutPositionWithTopLeftOrigin() {
        let background = solidBitmap(
            width: MainWindowLayout.windowWidth,
            height: MainWindowLayout.windowHeight,
            color: (10, 20, 30, 255)
        )

        var sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": background]
        ]

        // Give each element a unique color and its nominal size from the
        // sprite-coordinate table, so we can assert the exact landing pixel.
        var expectedColors: [Int: (UInt8, UInt8, UInt8, UInt8)] = [:]
        for (offset, element) in MainWindowLayout.elements.enumerated() {
            guard
                let rects = SpriteCoordinates.mainWindow[element.sheet],
                let rect = rects.first(where: { $0.name == element.sprite })
            else {
                XCTFail("\(element.sheet)/\(element.sprite) missing nominal size")
                return
            }
            let color: (UInt8, UInt8, UInt8, UInt8) = (UInt8(40 + offset), 100, 200, 255)
            expectedColors[offset] = color
            let sprite = solidBitmap(width: rect.width, height: rect.height, color: color)
            sheets[element.sheet, default: [:]][element.sprite] = sprite
        }

        guard let composed = MainWindowComposer.compose(makeSkin(sprites: sheets)) else {
            XCTFail("compose returned nil for a skin with a background")
            return
        }

        XCTAssertEqual(composed.width, MainWindowLayout.windowWidth)
        XCTAssertEqual(composed.height, MainWindowLayout.windowHeight)

        for (offset, element) in MainWindowLayout.elements.enumerated() {
            let expected = expectedColors[offset]!
            let landed = pixel(composed, x: element.x, y: element.y)
            XCTAssertEqual(
                landed.0, expected.0,
                "\(element.sheet)/\(element.sprite) wrong red at (\(element.x),\(element.y))")
            XCTAssertEqual(landed.1, expected.1)
            XCTAssertEqual(landed.2, expected.2)
            XCTAssertEqual(landed.3, expected.3)
        }
    }

    // MARK: - 2. Draw order

    /// Two overlapping elements: the one drawn later (front) must win in the
    /// overlap region.
    func testLaterElementWinsInOverlapRegion() {
        let background = solidBitmap(width: 20, height: 20, color: (0, 0, 0, 255))

        let backColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
        let frontColor: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)

        let sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": background],
            "back.bmp": ["a": solidBitmap(width: 10, height: 10, color: backColor)],
            "front.bmp": ["b": solidBitmap(width: 10, height: 10, color: frontColor)]
        ]

        let elements = [
            WindowElement(sheet: "back.bmp", sprite: "a", x: 0, y: 0),
            WindowElement(sheet: "front.bmp", sprite: "b", x: 5, y: 5)
        ]

        guard let composed = MainWindowComposer.compose(
            makeSkin(sprites: sheets),
            elements: elements
        ) else {
            XCTFail("compose returned nil")
            return
        }

        // Overlap region (5,5)..(9,9) belongs to the front element.
        XCTAssertEqual(pixel(composed, x: 7, y: 7).1, frontColor.1)
        XCTAssertEqual(pixel(composed, x: 7, y: 7).0, frontColor.0)
        // Back-only region (e.g. (1,1)) still belongs to the back element.
        XCTAssertEqual(pixel(composed, x: 1, y: 1).0, backColor.0)
    }

    // MARK: - 3. Missing sprite

    /// An element whose sprite is absent is skipped without crashing; the
    /// background shows through where it would have landed.
    func testMissingSpriteIsSkippedAndBackgroundShowsThrough() {
        let bgColor: (UInt8, UInt8, UInt8, UInt8) = (12, 34, 56, 255)
        let background = solidBitmap(width: 20, height: 20, color: bgColor)

        let sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": background]
        ]
        // The element points at a sheet/sprite that does not exist.
        let elements = [WindowElement(sheet: "nope.bmp", sprite: "ghost", x: 3, y: 4)]

        guard let composed = MainWindowComposer.compose(
            makeSkin(sprites: sheets),
            elements: elements
        ) else {
            XCTFail("compose returned nil")
            return
        }

        let landed = pixel(composed, x: 3, y: 4)
        XCTAssertEqual(landed.0, bgColor.0)
        XCTAssertEqual(landed.1, bgColor.1)
        XCTAssertEqual(landed.2, bgColor.2)
        XCTAssertEqual(landed.3, bgColor.3)
    }

    // MARK: - 4. Clipping

    /// A sprite positioned so it extends past the right and bottom edges is
    /// composited without crashing; its in-bounds part is copied and the
    /// out-of-range part is dropped.
    func testSpriteClippedAtRightAndBottomEdges() {
        let bgColor: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255)
        let background = solidBitmap(width: 10, height: 10, color: bgColor)

        let spriteColor: (UInt8, UInt8, UInt8, UInt8) = (200, 100, 50, 255)
        let sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": background],
            "over.bmp": ["edge": solidBitmap(width: 6, height: 6, color: spriteColor)]
        ]
        // Placed at (7,7): only the top-left 3x3 of the 6x6 sprite is in bounds.
        let elements = [WindowElement(sheet: "over.bmp", sprite: "edge", x: 7, y: 7)]

        guard let composed = MainWindowComposer.compose(
            makeSkin(sprites: sheets),
            elements: elements
        ) else {
            XCTFail("compose returned nil")
            return
        }

        // In-bounds part copied.
        XCTAssertEqual(pixel(composed, x: 7, y: 7).0, spriteColor.0)
        XCTAssertEqual(pixel(composed, x: 9, y: 9).0, spriteColor.0)
        // Just outside the sprite footprint stays background.
        XCTAssertEqual(pixel(composed, x: 6, y: 6).0, bgColor.0)
    }

    // MARK: - 5. No background

    /// A skin with no `main.bmp/background` yields `nil`.
    func testNoBackgroundReturnsNil() {
        let skin = makeSkin(sprites: [:])
        XCTAssertNil(MainWindowComposer.compose(skin))
    }

    // MARK: - 6. Background preserved

    /// Pixels not covered by any element still equal the background color.
    func testUncoveredPixelsKeepBackgroundColor() {
        let bgColor: (UInt8, UInt8, UInt8, UInt8) = (77, 88, 99, 255)
        let background = solidBitmap(width: 20, height: 20, color: bgColor)

        let sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": background],
            "tiny.bmp": ["dot": solidBitmap(width: 4, height: 4, color: opaqueWhite)]
        ]
        let elements = [WindowElement(sheet: "tiny.bmp", sprite: "dot", x: 0, y: 0)]

        guard let composed = MainWindowComposer.compose(
            makeSkin(sprites: sheets),
            elements: elements
        ) else {
            XCTFail("compose returned nil")
            return
        }

        // Far corner is untouched by the 4x4 dot at the origin.
        let corner = pixel(composed, x: 19, y: 19)
        XCTAssertEqual(corner.0, bgColor.0)
        XCTAssertEqual(corner.1, bgColor.1)
        XCTAssertEqual(corner.2, bgColor.2)
        XCTAssertEqual(corner.3, bgColor.3)
    }

    // MARK: - 7. Undersized background

    /// A `main.bmp/background` whose backing buffer is shorter than its declared
    /// `width * height * 4` is malformed: copying it would read/write out of
    /// range and trap. `compose` must treat it as no usable background and return
    /// `nil` without crashing.
    func testUndersizedBackgroundReturnsNilWithoutCrashing() {
        // Declares 20x20 (1600 bytes) but only carries half a buffer.
        let undersized = DecodedBitmap(
            width: 20,
            height: 20,
            pixels: [UInt8](repeating: 0, count: 20 * 20 * 4 / 2)
        )
        let sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": undersized]
        ]

        XCTAssertNil(MainWindowComposer.compose(makeSkin(sprites: sheets)))
    }

    // MARK: - 8. Undersized element sprite

    /// A valid background plus one element whose sprite buffer is shorter than
    /// its declared dimensions: the malformed sprite is skipped (not copied,
    /// never traps) while the background and the other element still composite.
    func testUndersizedElementSpriteIsSkippedAndOthersComposite() {
        let bgColor: (UInt8, UInt8, UInt8, UInt8) = (12, 34, 56, 255)
        let background = solidBitmap(width: 20, height: 20, color: bgColor)

        // Declares 6x6 (864 bytes) but only carries 4 bytes — undersized.
        let malformed = DecodedBitmap(width: 6, height: 6, pixels: [0, 0, 0, 255])

        let goodColor: (UInt8, UInt8, UInt8, UInt8) = (200, 100, 50, 255)
        let sheets: [String: [String: DecodedBitmap]] = [
            "main.bmp": ["background": background],
            "bad.bmp": ["broken": malformed],
            "good.bmp": ["dot": solidBitmap(width: 4, height: 4, color: goodColor)]
        ]
        let elements = [
            WindowElement(sheet: "bad.bmp", sprite: "broken", x: 0, y: 0),
            WindowElement(sheet: "good.bmp", sprite: "dot", x: 10, y: 10)
        ]

        guard let composed = MainWindowComposer.compose(
            makeSkin(sprites: sheets),
            elements: elements
        ) else {
            XCTFail("compose returned nil for a skin with a valid background")
            return
        }

        // The malformed sprite was skipped: its footprint at (0,0) stays
        // background.
        let skipped = pixel(composed, x: 0, y: 0)
        XCTAssertEqual(skipped.0, bgColor.0)
        XCTAssertEqual(skipped.1, bgColor.1)
        XCTAssertEqual(skipped.2, bgColor.2)
        XCTAssertEqual(skipped.3, bgColor.3)

        // The valid sprite still composited at its position.
        let good = pixel(composed, x: 10, y: 10)
        XCTAssertEqual(good.0, goodColor.0)
        XCTAssertEqual(good.1, goodColor.1)
        XCTAssertEqual(good.2, goodColor.2)
        XCTAssertEqual(good.3, goodColor.3)

        // An uncovered pixel still equals the background.
        let corner = pixel(composed, x: 19, y: 0)
        XCTAssertEqual(corner.0, bgColor.0)
    }
}
