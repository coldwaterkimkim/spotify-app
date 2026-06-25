import XCTest
@testable import UltraDolmengCore

final class SpotifyQueueModelTests: XCTestCase {
    func testQueueResponseDecodesTracksAndEpisodes() throws {
        let data = """
        {
          "queue": [
            {
              "id": "track-1",
              "uri": "spotify:track:track-1",
              "name": "Next Song",
              "type": "track",
              "duration_ms": 213000,
              "album": { "name": "Next Album" },
              "artists": [
                { "name": "First Artist" },
                { "name": "Second Artist" }
              ]
            },
            {
              "id": "episode-1",
              "uri": "spotify:episode:episode-1",
              "name": "Next Episode",
              "type": "episode",
              "show": { "name": "Great Show" },
              "publisher": "Fallback Publisher"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SpotifyQueueResponse.self, from: data)
        let items = response.queueItems()

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Next Song")
        XCTAssertEqual(items[0].artist, "First Artist, Second Artist")
        XCTAssertEqual(items[0].uri, "spotify:track:track-1")
        XCTAssertEqual(items[0].album, "Next Album")
        XCTAssertEqual(items[0].durationMilliseconds, 213000)
        XCTAssertEqual(items[1].title, "Next Episode")
        XCTAssertEqual(items[1].artist, "Great Show")
        XCTAssertEqual(items[1].uri, "spotify:episode:episode-1")
    }

}
