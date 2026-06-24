import Foundation
import XCTest
@testable import SkinKit

/// Tests for `SkinLoader.load(_:decoder:)`, the capstone that assembles a
/// `Skin` from a `.wsz` archive using an injected bitmap decoder.
///
/// These stay in the pure core target: instead of a real image decoder, a
/// `StubDecoder` interprets a tiny synthetic header (width/height) so a "sheet"
/// can declare its own decoded size, and synthetic archives are built with
/// `ZipFixtureBuilder`. The seven tests map one-to-one to the acceptance
/// criteria, called out in each `MARK`.
final class SkinLoaderTests: XCTestCase {

    // MARK: - Stub decoder

    /// A `BitmapDecoding` that decodes a 4-byte synthetic header — width (UInt16
    /// LE) then height (UInt16 LE) — into a `DecodedBitmap` of exactly that size,
    /// filled with a deterministic pattern (R = x, G = y, B = 0, A = 255). This
    /// lets each synthetic sheet declare a size large enough for its sprite
    /// rects, while staying free of any real image framework.
    ///
    /// A sheet whose name is listed in `undecodable` decodes to `nil`, exercising
    /// the fault-tolerant "skip the sheet" path.
    private struct StubDecoder: BitmapDecoding {
        /// Bytes (the synthetic header) whose decode must fail, by exact match.
        var undecodableHeaders: Set<Data> = []

        func decode(_ data: Data) -> DecodedBitmap? {
            if undecodableHeaders.contains(data) { return nil }
            guard data.count >= 4 else { return nil }
            let bytes = Array(data)
            let width = Int(bytes[0]) | (Int(bytes[1]) << 8)
            let height = Int(bytes[2]) | (Int(bytes[3]) << 8)
            guard width > 0, height > 0 else { return nil }

            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    pixels[i + 0] = UInt8(x & 0xFF)
                    pixels[i + 1] = UInt8(y & 0xFF)
                    pixels[i + 2] = 0
                    pixels[i + 3] = 255
                }
            }
            return DecodedBitmap(width: width, height: height, pixels: pixels)
        }
    }

    // MARK: - Synthetic-sheet header

    /// A 4-byte synthetic "sheet" the `StubDecoder` understands: the requested
    /// width and height as little-endian `UInt16`s.
    private func sheetBytes(width: Int, height: Int) -> Data {
        Data([
            UInt8(width & 0xFF), UInt8((width >> 8) & 0xFF),
            UInt8(height & 0xFF), UInt8((height >> 8) & 0xFF)
        ])
    }

    /// A stored (uncompressed) archive entry for the given path and bytes.
    private func entry(_ path: String, _ payload: Data) -> ZipFixtureBuilder.Entry {
        ZipFixtureBuilder.Entry(path: path, payload: payload, method: .stored)
    }

    /// A stored text archive entry, UTF-8 encoded.
    private func textEntry(_ path: String, _ text: String) -> ZipFixtureBuilder.Entry {
        entry(path, Data(text.utf8))
    }

    // MARK: - Standard config fixtures

    private let visColorText = """
    0,0,0
    255,255,255
    24,33,41
    """

    private let pleditText = """
    [Text]
    Normal=#00FF00
    Current=#FFFFFF
    Font=Arial
    """

    private let regionText = """
    [Normal]
    NumPoints=4
    PointList=0,0 10,0 10,10 0,10
    """

    // MARK: - Criterion 1: happy path

    func testHappyPathReturnsSpritesAndConfigs() throws {
        // cbuttons.bmp needs to fit play at (23,0,23,18) -> at least 115x36;
        // numbers.bmp needs digit0 at (0,0,9,13) -> at least 90x13.
        let data = ZipFixtureBuilder.build(entries: [
            entry("cbuttons.bmp", sheetBytes(width: 115, height: 36)),
            entry("numbers.bmp", sheetBytes(width: 90, height: 13)),
            textEntry("viscolor.txt", visColorText),
            textEntry("pledit.txt", pleditText),
            textEntry("region.txt", regionText)
        ])

        let skin = try SkinLoader.load(data, decoder: StubDecoder())

        XCTAssertNotNil(skin.sprites["cbuttons.bmp"]?["play"])
        XCTAssertNotNil(skin.sprites["numbers.bmp"]?["digit0"])
        XCTAssertFalse(skin.visColors.isEmpty)
        XCTAssertNotNil(skin.playlist)
        XCTAssertNotNil(skin.region)
        XCTAssertEqual(skin.playlist?.font, "Arial")
        XCTAssertEqual(skin.region?.polygons.count, 1)
    }

    // MARK: - Criterion 2: not an archive

    func testNonArchiveDataThrowsNotAZipArchive() {
        let randomBytes = Data((0..<256).map { _ in UInt8.random(in: 0...255) })
        XCTAssertThrowsError(try SkinLoader.load(randomBytes, decoder: StubDecoder())) { error in
            XCTAssertEqual(error as? ZipError, .notAZipArchive)
        }
    }

    // MARK: - Criterion 3: missing sheet

    func testMissingSheetIsAbsentOthersStillCut() throws {
        // Only numbers.bmp is present; cbuttons.bmp is absent.
        let data = ZipFixtureBuilder.build(entries: [
            entry("numbers.bmp", sheetBytes(width: 90, height: 13))
        ])

        let skin = try SkinLoader.load(data, decoder: StubDecoder())

        XCTAssertNil(skin.sprites["cbuttons.bmp"])
        XCTAssertNotNil(skin.sprites["numbers.bmp"]?["digit0"])
    }

    // MARK: - Criterion 4: undecodable sheet

    func testUndecodableSheetIsAbsentOthersStillCut() throws {
        let badHeader = sheetBytes(width: 115, height: 36)
        let data = ZipFixtureBuilder.build(entries: [
            entry("cbuttons.bmp", badHeader),
            entry("numbers.bmp", sheetBytes(width: 90, height: 13))
        ])
        let decoder = StubDecoder(undecodableHeaders: [badHeader])

        let skin = try SkinLoader.load(data, decoder: decoder)

        XCTAssertNil(skin.sprites["cbuttons.bmp"])
        XCTAssertNotNil(skin.sprites["numbers.bmp"]?["digit0"])
    }

    // MARK: - Criterion 5: missing configs

    func testMissingConfigsYieldEmptyAndNil() throws {
        let data = ZipFixtureBuilder.build(entries: [
            entry("numbers.bmp", sheetBytes(width: 90, height: 13))
        ])

        let skin = try SkinLoader.load(data, decoder: StubDecoder())

        XCTAssertEqual(skin.visColors, [])
        XCTAssertNil(skin.playlist)
        XCTAssertNil(skin.region)
    }

    // MARK: - Criterion 6: cross-sheet namespacing

    func testSpriteNameSharedAcrossSheetsIsIndependentlyRetrievable() throws {
        // "play" exists in cbuttons.bmp (23,0,23,18) and playpaus.bmp (0,0,9,9).
        let data = ZipFixtureBuilder.build(entries: [
            entry("cbuttons.bmp", sheetBytes(width: 115, height: 36)),
            entry("playpaus.bmp", sheetBytes(width: 42, height: 9))
        ])

        let skin = try SkinLoader.load(data, decoder: StubDecoder())

        let fromButtons = skin.sprite(sheet: "cbuttons.bmp", name: "play")
        let fromStatus = skin.sprite(sheet: "playpaus.bmp", name: "play")
        XCTAssertNotNil(fromButtons)
        XCTAssertNotNil(fromStatus)
        // The transport "play" is 23x18; the status "play" glyph is 9x9 — they
        // must not be the same bitmap.
        XCTAssertEqual(fromButtons?.width, 23)
        XCTAssertEqual(fromButtons?.height, 18)
        XCTAssertEqual(fromStatus?.width, 9)
        XCTAssertEqual(fromStatus?.height, 9)
        XCTAssertNotEqual(fromButtons, fromStatus)
    }

    // MARK: - Criterion 7: Latin1 config fallback

    func testLatin1ConfigStillParses() throws {
        // A pledit.txt whose Font value contains a 0xE9 byte ("é" in Latin1).
        // That byte is invalid UTF-8, so a UTF-8-only read would drop the whole
        // file; the loader must fall back to Latin1 and still parse the section.
        var pleditBytes = Data("[Text]\nNormal=#112233\nFont=Caf".utf8)
        pleditBytes.append(0xE9)            // 'é' in Latin1, invalid in UTF-8
        pleditBytes.append(contentsOf: Data("\n".utf8))

        XCTAssertNil(String(data: pleditBytes, encoding: .utf8),
                     "fixture must be invalid UTF-8 to exercise the fallback")

        let data = ZipFixtureBuilder.build(entries: [
            entry("numbers.bmp", sheetBytes(width: 90, height: 13)),
            entry("pledit.txt", pleditBytes)
        ])

        let skin = try SkinLoader.load(data, decoder: StubDecoder())

        XCTAssertNotNil(skin.playlist)
        XCTAssertEqual(skin.playlist?.normalText, RGBColor(r: 0x11, g: 0x22, b: 0x33))
        XCTAssertEqual(skin.playlist?.font, "Café")
    }
}
