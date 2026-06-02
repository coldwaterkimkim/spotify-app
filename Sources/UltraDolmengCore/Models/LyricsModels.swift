import Foundation

struct LyricsLine: Equatable, Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LyricsPayload: Equatable {
    case synced([LyricsLine])
    case plain([String])
    case missing
}

struct CaptionLines: Equatable {
    let current: String
    let next: String?
    let isFallback: Bool

    static let empty = CaptionLines(current: "", next: nil, isFallback: false)
}

struct LRCLIBRecord: Decodable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
}

struct LyricsCacheKey: Hashable {
    let title: String
    let artist: String
    let album: String

    var storageIdentifier: String {
        [title, artist, album].joined(separator: "\n")
    }

    init(track: TrackInfo) {
        self.init(title: track.title, artist: track.artist, album: track.album)
    }

    init(queueItem: QueueItemInfo) {
        self.init(title: queueItem.title, artist: queueItem.artist, album: queueItem.album)
    }

    private init(title: String, artist: String, album: String?) {
        self.title = Self.normalized(title)
        self.artist = Self.normalized(artist)
        self.album = Self.normalized(album ?? "")
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
