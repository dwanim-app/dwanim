import Foundation

// MARK: - PlaylistColors

/// The color and font settings for the playlist window, as carried by
/// `pledit.txt` in the classic `.wsz` skin format.
///
/// Every field is optional: a missing key in the file leaves its field `nil`,
/// and a file with no recognizable section leaves all fields `nil`. The loader
/// is expected to fall back to defaults for any `nil`.
public struct PlaylistColors: Sendable, Equatable {
    /// Color of unselected playlist entry text.
    public let normalText: RGBColor?
    /// Color of the currently playing entry's text.
    public let currentText: RGBColor?
    /// Background color behind unselected entries.
    public let normalBackground: RGBColor?
    /// Background color behind the selected entry.
    public let selectedBackground: RGBColor?
    /// Name of the font used for playlist text, verbatim from the file.
    public let font: String?

    public init(
        normalText: RGBColor?,
        currentText: RGBColor?,
        normalBackground: RGBColor?,
        selectedBackground: RGBColor?,
        font: String?
    ) {
        self.normalText = normalText
        self.currentText = currentText
        self.normalBackground = normalBackground
        self.selectedBackground = selectedBackground
        self.font = font
    }
}
