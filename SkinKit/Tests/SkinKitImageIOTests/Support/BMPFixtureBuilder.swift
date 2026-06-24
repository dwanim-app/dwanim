import Foundation

/// Assembles raw uncompressed BMP bytes programmatically so tests never depend
/// on real image files. This builder is the executable specification for the
/// subset of the BMP format used to exercise the decoder: a BITMAPFILEHEADER, a
/// BITMAPINFOHEADER, optional palette, and bottom-up pixel rows padded to a
/// 4-byte boundary.
///
/// Only the fields a decoder actually consults are populated with meaningful
/// values; the layout is deliberately explicit so the on-disk format is
/// auditable from the test alone.
enum BMPFixtureBuilder {

    // MARK: - Header sizes

    private static let fileHeaderSize = 14
    private static let infoHeaderSize = 40

    // MARK: - 24-bit (true color)

    /// Builds a 24-bit uncompressed BMP. `rows` is given top-to-bottom; the
    /// builder writes them bottom-up as the format requires. Each pixel is
    /// `(r, g, b)` and is stored on disk as BGR.
    static func bmp24(width: Int, height: Int, rows: [[(r: UInt8, g: UInt8, b: UInt8)]]) -> Data {
        precondition(rows.count == height, "row count must equal height")

        let rowStride = paddedRowStride(bitsPerPixel: 24, width: width)
        var pixelData = Data()

        // BMP stores rows bottom-up, so emit the supplied top-down rows in reverse.
        for row in rows.reversed() {
            precondition(row.count == width, "each row must have `width` pixels")
            var rowBytes = Data()
            for pixel in row {
                rowBytes.append(pixel.b)
                rowBytes.append(pixel.g)
                rowBytes.append(pixel.r)
            }
            while rowBytes.count < rowStride { rowBytes.append(0) }
            pixelData.append(rowBytes)
        }

        return assemble(
            width: width,
            height: height,
            bitsPerPixel: 24,
            palette: Data(),
            paletteEntryCount: 0,
            pixelData: pixelData
        )
    }

    // MARK: - 8-bit (palette)

    /// Builds an 8-bit palette BMP. `palette` lists colors as `(r, g, b)`;
    /// `rows` (top-to-bottom) hold palette indices. Stored bottom-up with each
    /// row padded to a 4-byte boundary.
    static func bmp8(
        width: Int,
        height: Int,
        palette: [(r: UInt8, g: UInt8, b: UInt8)],
        rows: [[UInt8]]
    ) -> Data {
        precondition(rows.count == height, "row count must equal height")

        var paletteData = Data()
        for color in palette {
            // BMP palette entries are stored as B, G, R, reserved.
            paletteData.append(color.b)
            paletteData.append(color.g)
            paletteData.append(color.r)
            paletteData.append(0)
        }

        let rowStride = paddedRowStride(bitsPerPixel: 8, width: width)
        var pixelData = Data()
        for row in rows.reversed() {
            precondition(row.count == width, "each row must have `width` indices")
            var rowBytes = Data(row)
            while rowBytes.count < rowStride { rowBytes.append(0) }
            pixelData.append(rowBytes)
        }

        return assemble(
            width: width,
            height: height,
            bitsPerPixel: 8,
            palette: paletteData,
            paletteEntryCount: palette.count,
            pixelData: pixelData
        )
    }

    // MARK: - Assembly

    private static func assemble(
        width: Int,
        height: Int,
        bitsPerPixel: UInt16,
        palette: Data,
        paletteEntryCount: Int,
        pixelData: Data
    ) -> Data {
        let pixelOffset = fileHeaderSize + infoHeaderSize + palette.count
        let fileSize = pixelOffset + pixelData.count

        var data = Data()

        // BITMAPFILEHEADER
        data.append(0x42)                              // 'B'
        data.append(0x4D)                              // 'M'
        data.appendLE(UInt32(fileSize))                // file size
        data.appendLE(UInt16(0))                       // reserved 1
        data.appendLE(UInt16(0))                       // reserved 2
        data.appendLE(UInt32(pixelOffset))             // pixel data offset

        // BITMAPINFOHEADER
        data.appendLE(UInt32(infoHeaderSize))          // header size
        data.appendLE(Int32(width))                    // width
        data.appendLE(Int32(height))                   // height (positive = bottom-up)
        data.appendLE(UInt16(1))                       // color planes
        data.appendLE(bitsPerPixel)                    // bits per pixel
        data.appendLE(UInt32(0))                       // compression (BI_RGB)
        data.appendLE(UInt32(pixelData.count))         // image size
        data.appendLE(Int32(2835))                     // x pixels-per-meter (~72 dpi)
        data.appendLE(Int32(2835))                     // y pixels-per-meter
        data.appendLE(UInt32(paletteEntryCount))       // colors used
        data.appendLE(UInt32(0))                       // important colors

        data.append(palette)
        data.append(pixelData)
        return data
    }

    // MARK: - Row stride

    /// Bytes per pixel row, rounded up to the nearest 4-byte boundary as the
    /// BMP format requires.
    private static func paddedRowStride(bitsPerPixel: Int, width: Int) -> Int {
        let bits = bitsPerPixel * width
        let bytes = (bits + 7) / 8
        return (bytes + 3) & ~3
    }
}

// MARK: - Little-endian append helpers

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendLE(_ value: Int32) {
        appendLE(UInt32(bitPattern: value))
    }
}
