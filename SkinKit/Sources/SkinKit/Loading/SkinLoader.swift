import Foundation

// MARK: - SkinLoader

/// Assembles a `Skin` from raw `.wsz` archive bytes, using an injected bitmap
/// decoder (ADR-6: the core stays framework-neutral, so the concrete decoder is
/// supplied by the caller).
///
/// Fault tolerance is the rule. `load` throws **only** when the data is not a
/// usable archive at all — that single `ZipError.notAZipArchive` is allowed to
/// propagate from `SkinArchive`. Everything past that point degrades quietly: a
/// sheet that is missing or that the decoder rejects is simply absent from the
/// result; a missing or garbled config leaves its field empty/`nil`. The loader
/// never throws for those, and never crashes.
public enum SkinLoader {

    // MARK: - Loading

    /// Loads `data` into a `Skin`, cutting every known main-window sheet and
    /// parsing the three text configs.
    ///
    /// - Throws: `ZipError.notAZipArchive` only when `data` is not a usable
    ///   archive. No other error is thrown.
    public static func load(_ data: Data, decoder: BitmapDecoding) throws -> Skin {
        let archive = try SkinArchive(data: data)
        return Skin(
            sprites: loadSprites(from: archive, decoder: decoder),
            visColors: loadVisColors(from: archive),
            playlist: loadPlaylist(from: archive),
            region: loadRegion(from: archive)
        )
    }

    // MARK: - Sprites

    /// Cuts every sheet listed in `SpriteCoordinates.mainWindow`,
    /// `SpriteCoordinates.playlistWindow`, and `SpriteCoordinates.equalizerWindow`,
    /// keyed by the lowercased sheet filename. Each sheet is read and decoded
    /// **exactly once**; sheets that are absent or that the decoder rejects are
    /// omitted entirely (no empty entry is left behind).
    private static func loadSprites(
        from archive: SkinArchive,
        decoder: BitmapDecoding
    ) -> [String: [String: DecodedBitmap]] {
        var sprites: [String: [String: DecodedBitmap]] = [:]
        // The main-window, playlist-window, and equalizer-window tables key
        // disjoint sheets (no sheet filename appears in more than one), so a
        // single merged pass is unambiguous. The disjointness is enforced by a
        // unit test (SpriteCoordinatesTests) so this merge can never silently
        // double-process or clobber a shared sheet.
        let tables = [
            SpriteCoordinates.mainWindow,
            SpriteCoordinates.playlistWindow,
            SpriteCoordinates.equalizerWindow
        ]
        for (sheet, rects) in tables.flatMap({ $0 }) {
            guard let bytes = archive.file(named: sheet),
                  let bitmap = decoder.decode(bytes)
            else { continue }
            // A sheet may decode but yield nothing — e.g. it is so small that
            // every rect falls out of bounds. Per the doc above, such a sheet is
            // omitted entirely rather than stored as an empty dict.
            let cut = SpriteCutter.cut(bitmap, rects: rects)
            guard !cut.isEmpty else { continue }
            sprites[sheet.lowercased()] = cut
        }
        return sprites
    }

    // MARK: - Configs

    /// Parses `viscolor.txt`, or returns `[]` when it is absent/unreadable.
    private static func loadVisColors(from archive: SkinArchive) -> [RGBColor] {
        guard let text = text(named: "viscolor.txt", in: archive) else { return [] }
        return VisColorParser.parse(text)
    }

    /// Parses `pledit.txt`, or returns `nil` when it is absent/unreadable.
    private static func loadPlaylist(from archive: SkinArchive) -> PlaylistColors? {
        guard let text = text(named: "pledit.txt", in: archive) else { return nil }
        return PlaylistEditParser.parse(text)
    }

    /// Parses `region.txt`, or returns `nil` when it is absent/unreadable.
    private static func loadRegion(from archive: SkinArchive) -> SkinRegion? {
        guard let text = text(named: "region.txt", in: archive) else { return nil }
        return RegionParser.parse(text)
    }

    // MARK: - Text decoding

    /// Reads a config file and decodes it to a `String`, or `nil` if the file is
    /// absent.
    ///
    /// Real config files are frequently authored in a single-byte Western
    /// encoding rather than UTF-8, so UTF-8 is tried first and `isoLatin1` is the
    /// fallback. `isoLatin1` maps every one of the 256 byte values to a scalar,
    /// so it never fails — once the bytes are in hand, decoding always succeeds.
    private static func text(named name: String, in archive: SkinArchive) -> String? {
        guard let bytes = archive.file(named: name) else { return nil }
        if let utf8 = String(data: bytes, encoding: .utf8) { return utf8 }
        return String(data: bytes, encoding: .isoLatin1)
    }
}
