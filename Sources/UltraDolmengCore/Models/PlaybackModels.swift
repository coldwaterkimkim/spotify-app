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

struct QueueItemInfo: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let kind: String
    let uri: String?
    let album: String?
    let durationMilliseconds: Int?

    init(
        id: String,
        title: String,
        artist: String,
        kind: String,
        uri: String?,
        album: String? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.kind = kind
        self.uri = uri
        self.album = album
        self.durationMilliseconds = durationMilliseconds
    }

    func approximateTrackInfo(capturedAt: Date = Date()) -> TrackInfo {
        TrackInfo(
            id: uri ?? id,
            title: title,
            artist: artist,
            album: album,
            durationMilliseconds: durationMilliseconds ?? 180_000,
            progressMilliseconds: 0,
            isPlaying: true,
            capturedAt: capturedAt
        )
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

struct SpotifyQueueResponse: Decodable {
    let queue: [SpotifyQueueItem]
}

struct SpotifyQueueItem: Decodable {
    let id: String?
    let uri: String?
    let name: String?
    let type: String?
    let durationMilliseconds: Int?
    let album: SpotifyAlbum?
    let artists: [SpotifyArtist]?
    let show: SpotifyShow?
    let publisher: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uri
        case name
        case type
        case durationMilliseconds = "duration_ms"
        case album
        case artists
        case show
        case publisher
    }
}

struct SpotifyShow: Decodable {
    let name: String?
}

extension SpotifyPlaybackResponse {
    func trackInfo(capturedAt: Date = Date()) -> TrackInfo? {
        item?.trackInfo(
            progressMilliseconds: progressMilliseconds ?? 0,
            isPlaying: isPlaying,
            capturedAt: capturedAt
        )
    }
}

extension SpotifyTrackItem {
    func trackInfo(
        progressMilliseconds: Int = 0,
        isPlaying: Bool = false,
        capturedAt: Date = Date()
    ) -> TrackInfo? {
        guard type == nil || type == "track" else {
            return nil
        }

        let artistName = artists.map(\.name).joined(separator: ", ")
        return TrackInfo(
            id: id ?? "\(name)-\(artistName)",
            title: name,
            artist: artistName,
            album: album?.name,
            durationMilliseconds: durationMilliseconds,
            progressMilliseconds: progressMilliseconds,
            isPlaying: isPlaying,
            capturedAt: capturedAt
        )
    }
}

extension SpotifyQueueResponse {
    func queueItems() -> [QueueItemInfo] {
        queue.enumerated().compactMap { index, item in
            item.queueItemInfo(position: index)
        }
    }
}

private extension SpotifyQueueItem {
    func queueItemInfo(position: Int) -> QueueItemInfo? {
        guard let title = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false else {
            return nil
        }

        let artistNames = artists?.map(\.name).filter { $0.isEmpty == false }.joined(separator: ", ")
        let subtitle = [
            artistNames,
            show?.name,
            publisher
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { $0.isEmpty == false } ?? "Spotify"

        let identity = uri ?? id ?? "\(title)-\(subtitle)"
        return QueueItemInfo(
            id: "\(position)-\(identity)",
            title: title,
            artist: subtitle,
            kind: type ?? "track",
            uri: uri,
            album: album?.name,
            durationMilliseconds: durationMilliseconds
        )
    }
}
