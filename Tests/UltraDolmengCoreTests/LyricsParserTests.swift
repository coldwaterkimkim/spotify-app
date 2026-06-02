import XCTest
@testable import UltraDolmengCore

final class LyricsParserTests: XCTestCase {
    func testParsesSyncedLyricsWithFractions() {
        let lines = LyricsParser.parseSyncedLyrics("""
        [00:01.20]First line
        [00:03.500]Second line
        [01:05]Third line
        """)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time, 1.2, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 3.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 65, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "First line")
    }

    func testCaptionReturnsCurrentLineOnly() {
        let lines = [
            LyricsLine(time: 0, text: "current"),
            LyricsLine(time: 3, text: "next"),
            LyricsLine(time: 6, text: "later")
        ]

        let caption = LyricsParser.caption(for: .synced(lines), progress: 1.5, duration: 10, offset: 0)

        XCTAssertEqual(caption.current, "current")
        XCTAssertNil(caption.next)
        XCTAssertFalse(caption.isFallback)
    }

    func testPlainLyricsApproximateCurrentLineByDuration() {
        let caption = LyricsParser.caption(
            for: .plain(["first", "second", "third", "fourth"]),
            progress: 16,
            duration: 40,
            offset: 0
        )

        XCTAssertEqual(caption.current, "second")
        XCTAssertNil(caption.next)
        XCTAssertTrue(caption.isFallback)
    }
}
