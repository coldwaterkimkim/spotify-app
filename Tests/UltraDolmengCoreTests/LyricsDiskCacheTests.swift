import XCTest
@testable import UltraDolmengCore

final class LyricsDiskCacheTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    func testStoresAndLoadsSyncedLyrics() {
        let cache = LyricsDiskCache(directory: tempDirectory)
        let key = LyricsCacheKey(track: track)
        let payload = LyricsPayload.synced([
            LyricsLine(time: 1.2, text: "first"),
            LyricsLine(time: 3.4, text: "second")
        ])

        cache.store(payload, for: key)

        guard case .synced(let lines) = cache.lyrics(for: key) else {
            return XCTFail("Expected cached synced lyrics")
        }
        XCTAssertEqual(lines.map(\.time), [1.2, 3.4])
        XCTAssertEqual(lines.map(\.text), ["first", "second"])
    }

    func testNegativeCacheExpiresQuickly() throws {
        let cache = LyricsDiskCache(directory: tempDirectory, negativeTTL: 2)
        let key = LyricsCacheKey(track: track)

        cache.store(.missing, for: key)
        XCTAssertEqual(cache.lyrics(for: key), .missing)

        let expiredCache = LyricsDiskCache(directory: tempDirectory, negativeTTL: -1)
        XCTAssertNil(expiredCache.lyrics(for: key))
    }

    private var track: TrackInfo {
        TrackInfo(
            id: "track",
            title: "Next Level",
            artist: "E SENS",
            album: "The Anecdote",
            durationMilliseconds: 213_793,
            progressMilliseconds: 0,
            isPlaying: true,
            capturedAt: Date()
        )
    }
}
