import Foundation
import XCTest
@testable import SkinKit

/// Tests for the `Skin` value type — the assembled, fully decoded skin. These
/// pin down the namespaced sprite storage (sheet → name → bitmap) and the
/// `sprite(sheet:name:)` convenience lookup, independently of any loading.
final class SkinTests: XCTestCase {

    // MARK: - Helpers

    /// A 1x1 RGBA bitmap whose single pixel encodes `tag` in its red channel,
    /// so two distinct bitmaps are trivially distinguishable.
    private func bitmap(tag: UInt8) -> DecodedBitmap {
        DecodedBitmap(width: 1, height: 1, pixels: [tag, 0, 0, 255])
    }

    // MARK: - Storage shape

    func testSpritesAreNamespacedBySheet() {
        let sprites: [String: [String: DecodedBitmap]] = [
            "cbuttons.bmp": ["play": bitmap(tag: 1)],
            "numbers.bmp": ["digit0": bitmap(tag: 2)]
        ]
        let skin = Skin(sprites: sprites, visColors: [], playlist: nil, region: nil)

        XCTAssertEqual(skin.sprites["cbuttons.bmp"]?["play"], bitmap(tag: 1))
        XCTAssertEqual(skin.sprites["numbers.bmp"]?["digit0"], bitmap(tag: 2))
    }

    // MARK: - Convenience lookup

    func testSpriteLookupReturnsBitmapWhenPresent() {
        let skin = Skin(
            sprites: ["cbuttons.bmp": ["play": bitmap(tag: 7)]],
            visColors: [], playlist: nil, region: nil
        )
        XCTAssertEqual(skin.sprite(sheet: "cbuttons.bmp", name: "play"), bitmap(tag: 7))
    }

    func testSpriteLookupReturnsNilForMissingSheetOrName() {
        let skin = Skin(
            sprites: ["cbuttons.bmp": ["play": bitmap(tag: 7)]],
            visColors: [], playlist: nil, region: nil
        )
        XCTAssertNil(skin.sprite(sheet: "numbers.bmp", name: "play"))
        XCTAssertNil(skin.sprite(sheet: "cbuttons.bmp", name: "stop"))
    }

    // MARK: - Cross-sheet namespacing (no collision)

    func testSameSpriteNameInTwoSheetsDoesNotCollide() {
        let skin = Skin(
            sprites: [
                "cbuttons.bmp": ["play": bitmap(tag: 10)],
                "playpaus.bmp": ["play": bitmap(tag: 20)]
            ],
            visColors: [], playlist: nil, region: nil
        )

        XCTAssertEqual(skin.sprite(sheet: "cbuttons.bmp", name: "play"), bitmap(tag: 10))
        XCTAssertEqual(skin.sprite(sheet: "playpaus.bmp", name: "play"), bitmap(tag: 20))
    }

    // MARK: - Config fields are carried verbatim

    func testConfigFieldsArePreserved() {
        let colors = [RGBColor(r: 1, g: 2, b: 3)]
        let playlist = PlaylistColors(
            normalText: RGBColor(r: 4, g: 5, b: 6),
            currentText: nil, normalBackground: nil, selectedBackground: nil, font: "Arial"
        )
        let region = SkinRegion(polygons: [
            SkinRegion.Polygon(points: [SkinRegion.Point(x: 0, y: 0)])
        ])
        let skin = Skin(sprites: [:], visColors: colors, playlist: playlist, region: region)

        XCTAssertEqual(skin.visColors, colors)
        XCTAssertEqual(skin.playlist, playlist)
        XCTAssertEqual(skin.region, region)
    }
}
