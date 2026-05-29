import Foundation

struct TrackInfo: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let durationMilliseconds: Int
    let progressMilliseconds: Int
    let isPlaying: Bool
    let capturedAt: Date

    var displayTitle: String {
        "\(title) - \(artist)"
    }
}

enum PlaybackDisplayState: Equatable {
    case disconnected
    case idle
    case loading
    case playing(TrackInfo)
    case paused(TrackInfo)
    case error(String)
}

struct SpotifyPlaybackResponse: Decodable {
    let isPlaying: Bool
    let progressMilliseconds: Int?
    let item: SpotifyTrackItem?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMilliseconds = "progress_ms"
        case item
    }
}

struct SpotifyTrackItem: Decodable {
    let id: String?
    let name: String
    let durationMilliseconds: Int
    let album: SpotifyAlbum?
    let artists: [SpotifyArtist]
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMilliseconds = "duration_ms"
        case album
        case artists
        case type
    }
}

struct SpotifyAlbum: Decodable {
    let name: String?
}

struct SpotifyArtist: Decodable {
    let name: String
}

extension SpotifyPlaybackResponse {
    func trackInfo(capturedAt: Date = Date()) -> TrackInfo? {
        guard let item, item.type == nil || item.type == "track" else {
            return nil
        }

        return TrackInfo(
            id: item.id ?? "\(item.name)-\(item.artists.map(\.name).joined(separator: ","))",
            title: item.name,
            artist: item.artists.map(\.name).joined(separator: ", "),
            album: item.album?.name,
            durationMilliseconds: item.durationMilliseconds,
            progressMilliseconds: progressMilliseconds ?? 0,
            isPlaying: isPlaying,
            capturedAt: capturedAt
        )
    }
}
