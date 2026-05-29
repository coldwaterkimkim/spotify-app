import Foundation

struct LRCLIBClient {
    private let baseURL = URL(string: "https://lrclib.net/api")!

    func lyrics(for track: TrackInfo) async throws -> LyricsPayload {
        if let exact = try await exactLyrics(for: track) {
            return payload(from: exact)
        }

        let records = try await searchLyrics(for: track)
        if let best = records.first(where: { record in
            guard let synced = record.syncedLyrics else { return false }
            return synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }) ?? records.first {
            return payload(from: best)
        }

        return .missing
    }

    private func exactLyrics(for track: TrackInfo) async throws -> LRCLIBRecord? {
        var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "album_name", value: track.album ?? ""),
            URLQueryItem(name: "duration", value: "\(max(1, track.durationMilliseconds / 1000))")
        ]

        let (data, response) = try await URLSession.shared.data(for: request(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw LRCLIBError.invalidResponse
        }

        if http.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(http.statusCode) else {
            return nil
        }

        return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
    }

    private func searchLyrics(for track: TrackInfo) async throws -> [LRCLIBRecord] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title)
        ]

        let (data, response) = try await URLSession.shared.data(for: request(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw LRCLIBError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            return []
        }

        return try JSONDecoder().decode([LRCLIBRecord].self, from: data)
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("UltraDolmengSpotifyLyric/0.1 (macOS personal lyrics overlay)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func payload(from record: LRCLIBRecord) -> LyricsPayload {
        if let syncedLyrics = record.syncedLyrics {
            let lines = LyricsParser.parseSyncedLyrics(syncedLyrics)
            if lines.isEmpty == false {
                return .synced(lines)
            }
        }

        if let plainLyrics = record.plainLyrics {
            let lines = LyricsParser.parsePlainLyrics(plainLyrics)
            if lines.isEmpty == false {
                return .plain(lines)
            }
        }

        return .missing
    }
}

enum LRCLIBError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LRCLIB 응답을 읽지 못했어."
        }
    }
}
