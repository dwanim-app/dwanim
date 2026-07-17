import Foundation
import XCTest
@testable import PlayerCore

/// Tests for the pure `.m3u` reader/writer: the serialize format (header +
/// absolute paths + trailing newline), the tolerant parse (CRLF / blank lines /
/// `#` comments / `file://` lines), and the round-trip.
final class M3UPlaylistTests: XCTestCase {

    private let urls = [
        URL(fileURLWithPath: "/music/one.mp3"),
        URL(fileURLWithPath: "/music/deep/two three.flac"),
        URL(fileURLWithPath: "/other/four.m4a")
    ]

    // MARK: - Serialize

    func testSerializeWritesHeaderThenOnePathPerLineWithTrailingNewline() {
        let text = M3UPlaylist.serialize(urls)
        XCTAssertEqual(
            text,
            """
            #EXTM3U
            /music/one.mp3
            /music/deep/two three.flac
            /other/four.m4a

            """
        )
    }

    func testSerializeEmptyIsJustTheHeader() {
        XCTAssertEqual(M3UPlaylist.serialize([]), "#EXTM3U\n")
    }

    // MARK: - Parse

    func testParseRoundTripsSerializeOutput() {
        XCTAssertEqual(M3UPlaylist.parse(M3UPlaylist.serialize(urls)), urls)
    }

    func testParseSkipsHeaderCommentsAndBlankLines() {
        let text = """
        #EXTM3U

        # a comment
        /music/one.mp3

        #EXTINF:123,Some Title
        /music/deep/two three.flac
        """
        XCTAssertEqual(M3UPlaylist.parse(text), [urls[0], urls[1]])
    }

    func testParseToleratesCRLFAndSurroundingWhitespace() {
        let text = "#EXTM3U\r\n/music/one.mp3\r\n  /other/four.m4a  \r\n"
        XCTAssertEqual(M3UPlaylist.parse(text), [urls[0], urls[2]])
    }

    func testParseAcceptsFileURLLines() {
        let text = "file:///music/one.mp3\nfile:///music/deep/two%20three.flac\n"
        XCTAssertEqual(M3UPlaylist.parse(text), [urls[0], urls[1]])
    }

    func testParseEmptyOrCommentOnlyTextYieldsNothing() {
        XCTAssertEqual(M3UPlaylist.parse(""), [])
        XCTAssertEqual(M3UPlaylist.parse("#EXTM3U\n# nothing here\n"), [])
    }

    /// A leading UTF-8 BOM (U+FEFF) — the norm for Windows-exported .m3u8 —
    /// must be stripped: left in place it defeats the `#` comment check on the
    /// `#EXTM3U` header line, which then resolves to a phantom garbage track.
    func testParseStripsLeadingBOMWithoutPhantomEntry() {
        let text = "\u{FEFF}#EXTM3U\n/a/b.wav\n"
        XCTAssertEqual(M3UPlaylist.parse(text), [URL(fileURLWithPath: "/a/b.wav")])
    }
}
