import Foundation

// MARK: - WindowElement

/// One static control placed on the main window: the sprite to draw (by sheet
/// and name) and the top-left destination on the 275x116 window.
public struct WindowElement: Sendable, Equatable {
    /// Sheet filename the sprite is cut from, e.g. `"cbuttons.bmp"`.
    public let sheet: String
    /// Sprite name within that sheet, e.g. `"play"`.
    public let sprite: String
    /// Left edge of the sprite's destination on the 275x116 window.
    public let x: Int
    /// Top edge of the sprite's destination on the 275x116 window.
    public let y: Int

    public init(sheet: String, sprite: String, x: Int, y: Int) {
        self.sheet = sheet
        self.sprite = sprite
        self.x = x
        self.y = y
    }
}
