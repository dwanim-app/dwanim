import Foundation

// MARK: - RGBColor

/// An opaque 8-bit-per-channel RGB color, as carried by the text config files
/// of the classic `.wsz` skin format.
///
/// Channels are whole bytes in the range `0...255`. The type is deliberately
/// platform-neutral — it knows nothing of any rendering framework — so the core
/// stays `Foundation`-only and a UI layer can map it to its own color type.
public struct RGBColor: Sendable, Equatable {
    /// Red channel, `0...255`.
    public let r: UInt8
    /// Green channel, `0...255`.
    public let g: UInt8
    /// Blue channel, `0...255`.
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}
