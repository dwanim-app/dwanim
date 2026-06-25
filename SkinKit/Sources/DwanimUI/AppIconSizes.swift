import Foundation

// MARK: - AppIconSizes

/// The canonical macOS `.iconset` size table: the exact Apple file names mapped
/// to their PIXEL dimensions. This is the single source of truth shared by the
/// harness render mode (which writes one PNG per entry) and the unit test (which
/// guards against a dropped or renamed slot). Keeping it pure (no SwiftUI, no
/// AppKit) lets the slot list be asserted without rendering anything.
///
/// macOS uses five logical sizes (16, 32, 128, 256, 512 pt) each at 1x and 2x,
/// so ten files in total. Note the deliberate pixel collisions: the 2x of one
/// logical size equals the 1x of the next (32, 64, 256, 512 appear twice under
/// different names) — each is still rendered NATIVELY at that pixel size, never
/// downscaled from a larger render, so a 32px file is crisp 32px art.
public enum AppIconSizes {

    /// One `.iconset` slot: the Apple file name and its exact output pixel size.
    public struct Entry: Equatable, Sendable {
        /// The Apple `.iconset` file name, e.g. `icon_16x16@2x.png`.
        public let fileName: String
        /// The square output dimension in PIXELS (the PNG is `pixels`x`pixels`).
        public let pixels: Int

        public init(fileName: String, pixels: Int) {
            self.fileName = fileName
            self.pixels = pixels
        }
    }

    /// The ten canonical `.iconset` entries, in ascending logical order. Exactly
    /// the names `iconutil` / Icon Composer expect inside an `AppIcon.iconset`.
    public static let entries: [Entry] = [
        Entry(fileName: "icon_16x16.png", pixels: 16),
        Entry(fileName: "icon_16x16@2x.png", pixels: 32),
        Entry(fileName: "icon_32x32.png", pixels: 32),
        Entry(fileName: "icon_32x32@2x.png", pixels: 64),
        Entry(fileName: "icon_128x128.png", pixels: 128),
        Entry(fileName: "icon_128x128@2x.png", pixels: 256),
        Entry(fileName: "icon_256x256.png", pixels: 256),
        Entry(fileName: "icon_256x256@2x.png", pixels: 512),
        Entry(fileName: "icon_512x512.png", pixels: 512),
        Entry(fileName: "icon_512x512@2x.png", pixels: 1024)
    ]

    // MARK: - appiconset Contents.json

    /// One `images` element of an `AppIcon.appiconset/Contents.json`: a mac-idiom
    /// entry mapping a logical `size` at a `scale` to its `.iconset` filename.
    public struct AppIconSetImage: Equatable, Sendable {
        /// Always `"mac"` for the macOS app icon.
        public let idiom: String
        /// The logical point size as `"WxH"`, e.g. `"16x16"`.
        public let size: String
        /// `"1x"` or `"2x"`.
        public let scale: String
        /// The PNG file name (one of `entries`' `fileName`s).
        public let fileName: String

        public init(idiom: String, size: String, scale: String, fileName: String) {
            self.idiom = idiom
            self.size = size
            self.scale = scale
            self.fileName = fileName
        }
    }

    /// The five mac logical sizes, each at 1x and 2x, mapped to their PNG file
    /// names — the `images` array of `AppIcon.appiconset/Contents.json`. Ten
    /// entries, one per `.iconset` file, in the order `actool` expects.
    public static let appIconSetImages: [AppIconSetImage] = [
        AppIconSetImage(idiom: "mac", size: "16x16", scale: "1x", fileName: "icon_16x16.png"),
        AppIconSetImage(idiom: "mac", size: "16x16", scale: "2x", fileName: "icon_16x16@2x.png"),
        AppIconSetImage(idiom: "mac", size: "32x32", scale: "1x", fileName: "icon_32x32.png"),
        AppIconSetImage(idiom: "mac", size: "32x32", scale: "2x", fileName: "icon_32x32@2x.png"),
        AppIconSetImage(idiom: "mac", size: "128x128", scale: "1x", fileName: "icon_128x128.png"),
        AppIconSetImage(idiom: "mac", size: "128x128", scale: "2x", fileName: "icon_128x128@2x.png"),
        AppIconSetImage(idiom: "mac", size: "256x256", scale: "1x", fileName: "icon_256x256.png"),
        AppIconSetImage(idiom: "mac", size: "256x256", scale: "2x", fileName: "icon_256x256@2x.png"),
        AppIconSetImage(idiom: "mac", size: "512x512", scale: "1x", fileName: "icon_512x512.png"),
        AppIconSetImage(idiom: "mac", size: "512x512", scale: "2x", fileName: "icon_512x512@2x.png")
    ]
}
