import Foundation

// MARK: - SpriteCutter

/// Crops named rectangles out of a sprite sheet into individual bitmaps.
///
/// The engine is pure pixel arithmetic over RGBA8 buffers: it respects the
/// `width * 4` row stride and the top-left origin of `DecodedBitmap`, copying
/// each source row range into a fresh, tightly packed sprite buffer.
public enum SpriteCutter {

    // MARK: - Cutting

    /// Crops each rect from `sheet` into its own top-left-origin RGBA8 bitmap.
    ///
    /// A rect that does not fully fit within the sheet bounds — negative origin,
    /// non-positive size, or extending past the right/bottom edge — is
    /// **skipped** and omitted from the result rather than clamped or faulted.
    /// If two rects share a name, the last one wins.
    ///
    /// - Returns: A map from sprite name to its cropped bitmap.
    public static func cut(_ sheet: DecodedBitmap, rects: [SpriteRect]) -> [String: DecodedBitmap] {
        var sprites: [String: DecodedBitmap] = [:]
        for rect in rects {
            guard let sprite = crop(rect, from: sheet) else { continue }
            sprites[rect.name] = sprite
        }
        return sprites
    }

    // MARK: - Private

    /// Copies the sub-rectangle described by `rect` out of `sheet`, or returns
    /// `nil` when the rect is empty or not fully contained by the sheet.
    private static func crop(_ rect: SpriteRect, from sheet: DecodedBitmap) -> DecodedBitmap? {
        guard rect.width > 0, rect.height > 0, rect.x >= 0, rect.y >= 0 else { return nil }
        guard rect.x + rect.width <= sheet.width, rect.y + rect.height <= sheet.height else { return nil }

        let bytesPerPixel = 4
        // The rect is in-bounds for the *declared* size, but `DecodedBitmap`
        // does not enforce that its backing buffer actually holds
        // `width * height * bytesPerPixel` bytes. An undersized buffer would make
        // the unsafe row copies below read out of range and trap, so skip such a
        // malformed sheet rather than fault.
        guard sheet.pixels.count >= sheet.width * sheet.height * bytesPerPixel else { return nil }

        let sheetStride = sheet.width * bytesPerPixel
        let spriteStride = rect.width * bytesPerPixel

        var pixels = [UInt8](repeating: 0, count: rect.width * rect.height * bytesPerPixel)
        pixels.withUnsafeMutableBytes { dst in
            sheet.pixels.withUnsafeBytes { src in
                for row in 0..<rect.height {
                    let srcStart = (rect.y + row) * sheetStride + rect.x * bytesPerPixel
                    let dstStart = row * spriteStride
                    let srcRow = UnsafeRawBufferPointer(rebasing: src[srcStart ..< srcStart + spriteStride])
                    let dstRow = UnsafeMutableRawBufferPointer(rebasing: dst[dstStart ..< dstStart + spriteStride])
                    dstRow.copyMemory(from: srcRow)
                }
            }
        }
        return DecodedBitmap(width: rect.width, height: rect.height, pixels: pixels)
    }
}
