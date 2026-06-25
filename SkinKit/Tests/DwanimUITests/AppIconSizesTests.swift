import XCTest
import Foundation
@testable import DwanimUI

// MARK: - AppIconSizesTests

/// Guards the canonical macOS `.iconset` slot table and the committed
/// `AppIcon.appiconset/Contents.json` against each other. A dropped or renamed
/// slot, or a mismatch between the code's size table and the shipped asset
/// catalog, would silently produce an incomplete icon — actool can fail, or
/// (worse) the icon falls back to a generic placeholder. These checks catch that
/// at test time instead of at archive time.
final class AppIconSizesTests: XCTestCase {

    // MARK: - The canonical size table

    /// The slot table is EXACTLY the ten Apple-named entries at their pixel sizes,
    /// in ascending logical order. Asserted name-by-name (not just `.count`) so a
    /// typo or a wrong pixel size is caught, not just a missing slot.
    func testCanonicalSizeTableIsTheExactTen() {
        let expected: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        XCTAssertEqual(AppIconSizes.entries.count, 10)
        XCTAssertEqual(AppIconSizes.entries.count, expected.count)
        for (entry, expect) in zip(AppIconSizes.entries, expected) {
            XCTAssertEqual(entry.fileName, expect.0)
            XCTAssertEqual(entry.pixels, expect.1)
        }
    }

    /// File names are unique even though pixel sizes collide (32, 64?, 256, 512
    /// each appear under two different names). The collisions are intentional —
    /// the 2x of one logical size equals the 1x of the next — so the test asserts
    /// unique NAMES but allows duplicate pixel values.
    func testFileNamesAreUnique() {
        let names = AppIconSizes.entries.map(\.fileName)
        XCTAssertEqual(Set(names).count, names.count, "Duplicate .iconset file name")
    }

    /// The expected pixel collisions are present (a guard that the table still
    /// follows the 5-logical-sizes-at-1x/2x structure rather than ten distinct
    /// sizes).
    func testExpectedPixelCollisions() {
        let pixels = AppIconSizes.entries.map(\.pixels)
        XCTAssertEqual(pixels.filter { $0 == 32 }.count, 2)
        XCTAssertEqual(pixels.filter { $0 == 256 }.count, 2)
        XCTAssertEqual(pixels.filter { $0 == 512 }.count, 2)
        XCTAssertEqual(pixels.filter { $0 == 16 }.count, 1)
        XCTAssertEqual(pixels.filter { $0 == 1024 }.count, 1)
    }

    // MARK: - appiconset image map (in-code)

    /// The in-code `appIconSetImages` map has exactly ten mac-idiom entries, one
    /// per `.iconset` file, and every file name it references is a real slot.
    func testAppIconSetImageMapCoversAllTenSlots() {
        XCTAssertEqual(AppIconSizes.appIconSetImages.count, 10)

        let slotNames = Set(AppIconSizes.entries.map(\.fileName))
        let mappedNames = AppIconSizes.appIconSetImages.map(\.fileName)
        XCTAssertEqual(Set(mappedNames).count, 10, "Duplicate filename in appiconset map")
        for image in AppIconSizes.appIconSetImages {
            XCTAssertEqual(image.idiom, "mac")
            XCTAssertTrue(["1x", "2x"].contains(image.scale))
            XCTAssertTrue(slotNames.contains(image.fileName),
                          "appiconset references unknown slot \(image.fileName)")
        }

        // Every .iconset slot is referenced by at least one appiconset entry.
        XCTAssertEqual(Set(mappedNames), slotNames)
    }

    /// Each `size`x`scale` resolves to the pixel size of the file it points at:
    /// e.g. 16x16@2x must map to a 32px file. Catches a mis-wired scale/size pair.
    func testAppIconSetSizesResolveToSlotPixels() {
        let pixelsByName = Dictionary(
            uniqueKeysWithValues: AppIconSizes.entries.map { ($0.fileName, $0.pixels) }
        )
        for image in AppIconSizes.appIconSetImages {
            // size is "WxH" in logical points; W == H for these icons.
            let logical = Int(image.size.split(separator: "x").first ?? "")
            let multiplier = image.scale == "2x" ? 2 : 1
            let expectedPixels = (logical ?? 0) * multiplier
            XCTAssertEqual(pixelsByName[image.fileName], expectedPixels,
                           "\(image.size)@\(image.scale) -> \(image.fileName) pixel mismatch")
        }
    }

    // MARK: - Committed asset catalog on disk

    /// The committed `AppIcon.appiconset/Contents.json` maps ALL ten slots: ten
    /// `images` entries, each `mac`/1x|2x, each `filename` one of the canonical
    /// slots, and the set of referenced files equals the canonical slot set. This
    /// guards the shipped asset catalog against drifting from the code table (a
    /// dropped slot in the JSON would break actool's compile).
    func testCommittedAppIconSetContentsJSONMapsAllTen() throws {
        let url = try appIconSetContentsURL()
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            return XCTFail("Could not parse \(url.path) images array")
        }

        XCTAssertEqual(images.count, 10, "Expected 10 images in committed Contents.json")

        let slotNames = Set(AppIconSizes.entries.map(\.fileName))
        var referenced = Set<String>()
        for image in images {
            XCTAssertEqual(image["idiom"] as? String, "mac")
            let scale = image["scale"] as? String
            XCTAssertTrue(scale == "1x" || scale == "2x", "Bad scale \(scale ?? "nil")")
            guard let filename = image["filename"] as? String else {
                XCTFail("images entry missing filename: \(image)")
                continue
            }
            XCTAssertTrue(slotNames.contains(filename),
                          "Contents.json references unknown slot \(filename)")
            referenced.insert(filename)
        }
        XCTAssertEqual(referenced, slotNames,
                       "Committed Contents.json does not cover every canonical slot")

        // The top-level info block uses the xcode author/version actool expects.
        let info = root["info"] as? [String: Any]
        XCTAssertEqual(info?["author"] as? String, "xcode")
        XCTAssertEqual(info?["version"] as? Int, 1)
    }

    /// Every PNG the committed `Contents.json` names actually exists on disk next
    /// to it (the PNGs are source-controlled with the catalog).
    func testCommittedAppIconSetPNGsExist() throws {
        let contentsURL = try appIconSetContentsURL()
        let dir = contentsURL.deletingLastPathComponent()
        for entry in AppIconSizes.entries {
            let png = dir.appendingPathComponent(entry.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: png.path),
                          "Missing committed PNG \(png.path)")
        }
    }

    // MARK: - Locating the committed catalog

    /// Resolve the committed `App/Dwanim/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
    /// from this test file's location (`<repo>/SkinKit/Tests/DwanimUITests/...`).
    /// Skips the test (does not fail) if the repo layout is not present, so the
    /// suite stays green if run from an unexpected checkout.
    private func appIconSetContentsURL() throws -> URL {
        // …/SkinKit/Tests/DwanimUITests/AppIconSizesTests.swift
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // DwanimUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SkinKit
            .deletingLastPathComponent()  // repo root
        let url = repoRoot
            .appendingPathComponent("App/Dwanim/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: url.path),
            "Committed appiconset not found at \(url.path) (unexpected checkout layout)"
        )
        return url
    }
}
