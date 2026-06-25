import Foundation
import UniformTypeIdentifiers

// MARK: - DropRouter
//
// The pure, side-effect-free CLASSIFIER for a set of dropped file URLs. It splits
// the dropped `[URL]` into the two surfaces the app can open — `.wsz` SKINS and
// AUDIO files — and discards everything else. It performs NO I/O beyond the cheap
// UTType / extension probes and mints NO bookmarks: the app layer (`AudioSession`)
// owns the actual open + security-scoped bookmarking, exactly as the open-panel
// paths do. Keeping classification pure makes it trivially testable and keeps the
// drop policy in one readable place.
//
// ## Classification rules (mirrors the open panels)
//   - SKIN: a `.wsz` filename extension (case-insensitive). A `.wsz` carries no
//     system-declared UTI (this app deliberately does not claim it as a document
//     type — see project.yml), so the extension IS the signal. A `.zip` whose name
//     ends in `.wsz` is a skin; a plain `.zip` is NOT treated as a skin (we only
//     adopt the explicit skin extension to avoid swallowing arbitrary archives).
//   - AUDIO: a URL whose type conforms to one of the audio UTTypes the open panel
//     accepts (the broad `.audio` umbrella plus the common concrete types), OR
//     whose extension matches a known audio extension when the type can't be
//     resolved (a file with no type metadata still routes by extension, matching
//     how the engine opens it).
//   - Anything else is UNSUPPORTED and ignored gracefully.
//
// A drop that MIXES a skin + audio yields both buckets populated; the caller
// applies the skin AND loads the audio. Multiple audio files become the playlist
// (their drop ORDER is preserved). Multiple skins: only the FIRST is opened (a
// single skin is the active face — see `skins.first` at the call site); the rest
// are ignored.
enum DropRouter {

    /// The split result of classifying a dropped `[URL]`: the skin URLs (usually
    /// zero or one) and the audio URLs (in drop order), with everything else
    /// dropped. Empty buckets mean "nothing of that kind was dropped".
    struct Classification: Equatable {
        var skins: [URL]
        var audio: [URL]

        /// True when the drop contained nothing the app can open.
        var isEmpty: Bool { skins.isEmpty && audio.isEmpty }
    }

    /// The `.wsz` skin extension (lowercased for a case-insensitive compare).
    private static let skinExtension = "wsz"

    /// Known audio filename extensions used as the fallback when a URL exposes no
    /// resolvable content type. Mirrors the concrete types the open panel lists.
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "wave", "aif", "aiff", "aac", "m4a", "m4b", "mp4", "flac",
        "ogg", "oga", "opus", "caf", "aifc", "snd", "au"
    ]

    /// The audio UTTypes a dropped file's type is checked against (the broad
    /// umbrella plus the common concrete types — same set the audio open panel
    /// uses). Computed once.
    private static let audioContentTypes: [UTType] = {
        var types: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        if let flac = UTType("org.xiph.flac") { types.append(flac) }
        if let m4a = UTType("com.apple.m4a-audio") { types.append(m4a) }
        return types
    }()

    /// Classify `urls` into skins + audio, dropping unsupported types. Order is
    /// preserved within each bucket (so a multi-file audio drop keeps its drop
    /// order when it becomes the playlist).
    static func classify(_ urls: [URL]) -> Classification {
        var skins: [URL] = []
        var audio: [URL] = []
        for url in urls {
            if isSkin(url) {
                skins.append(url)
            } else if isAudio(url) {
                audio.append(url)
            }
            // else: unsupported — ignored gracefully.
        }
        return Classification(skins: skins, audio: audio)
    }

    // MARK: Probes

    /// A `.wsz` skin archive (by case-insensitive extension — a `.wsz` has no
    /// declared UTI, so the extension is the signal).
    private static func isSkin(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == skinExtension
    }

    /// An audio file: its resolved content type conforms to a known audio UTType,
    /// or (when the type can't be resolved) its extension is a known audio one.
    private static func isAudio(_ url: URL) -> Bool {
        if let type = resolvedType(of: url) {
            if audioContentTypes.contains(where: { type.conforms(to: $0) }) {
                return true
            }
            // A resolvable-but-non-audio type (e.g. an image) is not audio even if
            // its extension somehow collides; fall through to a negative.
            return false
        }
        // No resolvable type — route by extension so a file with absent type
        // metadata still opens (the engine opens it by content regardless).
        return audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// Resolve a URL's content type, preferring the on-disk type resource value and
    /// falling back to a type synthesized from the filename extension. `nil` when
    /// neither yields a type (then the extension fallback in `isAudio` applies).
    private static func resolvedType(of url: URL) -> UTType? {
        if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return resourceType
        }
        return UTType(filenameExtension: url.pathExtension)
    }
}
