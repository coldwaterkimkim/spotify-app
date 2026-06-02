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

    func testSavedTracksResponseDecodesLikedSongs() throws {
        let data = """
        {
          "href": "https://api.spotify.com/v1/me/tracks?offset=0&limit=50",
          "items": [
            {
              "added_at": "2026-05-30T00:00:00Z",
              "track": {
                "id": "liked-1",
                "name": "Liked Song",
                "type": "track",
                "duration_ms": 201000,
                "album": { "name": "Liked Album" },
                "artists": [
                  { "name": "Liked Artist" }
                ]
              }
            },
            {
              "added_at": "2026-05-30T00:01:00Z",
              "track": null
            }
          ],
          "limit": 50,
          "next": null,
          "offset": 0,
          "previous": null,
          "total": 2
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SpotifySavedTracksResponse.self, from: data)
        let tracks = response.trackInfos()

        XCTAssertEqual(response.total, 2)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "liked-1")
        XCTAssertEqual(tracks[0].title, "Liked Song")
        XCTAssertEqual(tracks[0].artist, "Liked Artist")
        XCTAssertEqual(tracks[0].album, "Liked Album")
        XCTAssertEqual(tracks[0].durationMilliseconds, 201000)
    }
}
