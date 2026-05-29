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
