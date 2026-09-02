import Foundation
import UniformTypeIdentifiers

// MARK: - DropRouter
//
// The pure, side-effect-free CLASSIFIER for a set of dropped OR opened file URLs
// (drag-drop AND the "Open With" / `open -a` path both route through it). It splits
// the `[URL]` into the surfaces the app can open — `.wsz` SKINS, `.m3u`/`.m3u8`
// PLAYLISTS, `.dwtheme`/`.dwskin` colour THEMES, FOLDERS, and AUDIO files — and
// discards everything else. It
// performs NO I/O beyond the cheap UTType / extension probes and mints NO
// bookmarks: the app layer (`AudioSession`) owns the actual open + security-scoped
// bookmarking (and the playlist parse), exactly as the open-panel paths do.
// Keeping classification pure makes it trivially testable and keeps the drop
// policy in one readable place.
//
// ## Classification rules (mirrors the open panels)
//   - SKIN: a `.wsz` filename extension (case-insensitive). The extension is the
//     signal (the app declares an imported UTI for `.wsz` so it appears in "Open
//     With", but classification here keys on the extension, uniform with the other
//     custom kinds). A `.zip` whose name ends in `.wsz` is a skin; a plain `.zip` is
//     NOT treated as a skin (we only adopt the explicit skin extension to avoid
//     swallowing arbitrary archives).
//   - THEME: a `.dwtheme` / `.dwskin` filename extension (case-insensitive) — a
//     nine-token COLOUR theme for the default face, applied via the App-owned
//     AppearanceStore. Distinct from a `.wsz` bitmap skin. Checked BEFORE the audio
//     probe (a theme is not audio).
//   - PLAYLIST: a `.m3u` / `.m3u8` filename extension (case-insensitive). Like
//     `.wsz` these carry no reliable system UTI, so the extension IS the signal.
//     The dropped playlist FILE is parsed to its listed tracks by the caller — a
//     `.m3u` is NOT audio, so it is checked BEFORE the audio probe.
//   - FOLDER: a DIRECTORY URL (by the on-disk `isDirectory` flag, falling back to
//     the URL's directory-path heuristic). A directory carries no audio UTI, so it
//     would otherwise be discarded as "unsupported"; instead it is routed to its
//     own bucket and the App tier enumerates its audio files (the "Add Folder…"
//     scan) and appends them. Checked BEFORE the audio probe.
//   - AUDIO: a URL whose type conforms to one of the audio UTTypes the open panel
//     accepts (the broad `.audio` umbrella plus the common concrete types), OR
//     whose extension matches a known audio extension when the type can't be
//     resolved (a file with no type metadata still routes by extension, matching
//     how the engine opens it).
//   - Anything else is UNSUPPORTED and ignored gracefully.
//
// A drop that MIXES a skin + playlist + audio yields every populated bucket; the
// caller applies the skin AND loads the playlist's tracks + the loose audio.
// Multiple audio files become the playlist (their drop ORDER is preserved), and
// playlist files keep their drop order too. Multiple skins: only the FIRST is
// opened (a single skin is the active face — see `skins.first` at the call site);
// the rest are ignored.
enum DropRouter {

    /// The split result of classifying a dropped `[URL]`: the skin URLs (usually
    /// zero or one), the playlist (`.m3u`/`.m3u8`) URLs, the FOLDER (directory)
    /// URLs, and the audio URLs (each in drop order), with everything else dropped.
    /// Empty buckets mean "nothing of that kind was dropped". The caller ENUMERATES
    /// each folder's audio files (the filesystem walk lives in the App tier, not in
    /// this pure classifier) and appends them alongside the loose audio.
    struct Classification: Equatable {
        var skins: [URL]
        var playlists: [URL]
        var themes: [URL]
        var folders: [URL]
        var audio: [URL]

        /// True when the drop contained nothing the app can open.
        var isEmpty: Bool {
            skins.isEmpty && playlists.isEmpty && themes.isEmpty
                && folders.isEmpty && audio.isEmpty
        }
    }

    /// The `.wsz` skin extension (lowercased for a case-insensitive compare).
    private static let skinExtension = "wsz"

    /// The colour-THEME extensions (lowercased, case-insensitive): the current
    /// `.dwtheme` and the legacy `.dwskin` (still opened for backward compat — see
    /// `AudioSession.appearanceContentTypes`). Like `.wsz`, a theme file carries no
    /// reliable system UTI, so the extension IS the signal. NOTE `.dwskin` is a
    /// COLOUR theme, distinct from the `.wsz` bitmap skin above — the two never
    /// collide (different extensions).
    private static let themeExtensions: Set<String> = ["dwtheme", "dwskin"]

    /// The `.m3u` / `.m3u8` playlist extensions (lowercased for a case-insensitive
    /// compare). Like `.wsz`, a playlist file carries no reliable system UTI, so
    /// the extension IS the signal.
    private static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

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

    /// Classify `urls` into skins + playlists + audio, dropping unsupported types.
    /// Order is preserved within each bucket (so a multi-file audio drop keeps its
    /// drop order when it becomes the playlist, and playlist files keep theirs).
    static func classify(_ urls: [URL]) -> Classification {
        var skins: [URL] = []
        var playlists: [URL] = []
        var themes: [URL] = []
        var folders: [URL] = []
        var audio: [URL] = []
        for url in urls {
            // Check order per URL: skin → playlist → theme → folder → audio. A
            // `.m3u` / `.dwtheme` is not audio, but classifying them BEFORE the audio
            // probe keeps the intent explicit; a directory is recognised BEFORE the
            // audio probe so a dropped folder routes to enumeration instead of being
            // discarded as a non-audio type (a directory's content type never
            // conforms to audio).
            if isSkin(url) {
                skins.append(url)
            } else if isPlaylist(url) {
                playlists.append(url)
            } else if isTheme(url) {
                themes.append(url)
            } else if isFolder(url) {
                folders.append(url)
            } else if isAudio(url) {
                audio.append(url)
            }
            // else: unsupported — ignored gracefully.
        }
        return Classification(
            skins: skins, playlists: playlists, themes: themes,
            folders: folders, audio: audio
        )
    }

    // MARK: Probes

    /// A `.wsz` skin archive (by case-insensitive extension — a `.wsz` has no
    /// declared UTI, so the extension is the signal).
    private static func isSkin(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == skinExtension
    }

    /// A `.m3u` / `.m3u8` playlist file (by case-insensitive extension — like
    /// `.wsz`, a playlist has no declared UTI, so the extension is the signal).
    private static func isPlaylist(_ url: URL) -> Bool {
        playlistExtensions.contains(url.pathExtension.lowercased())
    }

    /// A `.dwtheme` / `.dwskin` COLOUR-theme file (by case-insensitive extension —
    /// like `.wsz`, a theme has no declared system UTI, so the extension is the
    /// signal). Distinct from `isSkin` (`.wsz` bitmap skin).
    private static func isTheme(_ url: URL) -> Bool {
        themeExtensions.contains(url.pathExtension.lowercased())
    }

    /// A DIRECTORY (dropped folder) whose audio files the caller should enumerate.
    /// Prefers the authoritative on-disk `isDirectory` resource value (the same
    /// cheap filesystem probe `resolvedType` already uses), falling back to the
    /// URL's own directory-path heuristic when the flag can't be read — so a folder
    /// is recognised whether or not the drag delivered a trailing-slash URL.
    private static func isFolder(_ url: URL) -> Bool {
        if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
            return isDir
        }
        return url.hasDirectoryPath
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
