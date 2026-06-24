import Foundation

// MARK: - Track

/// A single item in a playlist: a file location plus optional metadata.
///
/// The type is deliberately platform-neutral — it carries only a `URL` and a
/// couple of optional descriptors — so the playback core stays `Foundation`-only
/// and knows nothing of any audio or UI framework. In M1 the metadata fields may
/// be `nil`; a later metadata pass can populate them.
public struct Track: Sendable, Equatable {
    /// The file location to play.
    public let url: URL
    /// Human-readable title, if known.
    public var title: String?
    /// Track length in seconds, if known ahead of playback.
    public var duration: TimeInterval?

    public init(url: URL, title: String? = nil, duration: TimeInterval? = nil) {
        self.url = url
        self.title = title
        self.duration = duration
    }
}
