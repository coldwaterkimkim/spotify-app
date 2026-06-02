import Foundation

struct LRCLIBClient {
    private let baseURL = URL(string: "https://lrclib.net/api")!
    private let session: URLSession
    private let fallbackDelayNanoseconds: UInt64

    init(
        session: URLSession = LRCLIBClient.makeFastSession(),
        fallbackDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.session = session
        self.fallbackDelayNanoseconds = fallbackDelayNanoseconds
    }

    func lyrics(for track: TrackInfo) async throws -> LyricsPayload {
        let summary = await firstRenderablePayload(from: [
            { try await exactLyrics(for: track, includesAlbum: false) },
            { try await bestSearchLyrics(for: track, query: .fields) },
            delayedLookup {
                try await exactLyrics(for: track, includesAlbum: true)
            },
            delayedLookup {
                try await bestSearchLyrics(for: track, query: .text("\(track.title) \(track.artist)"))
            },
            delayedLookup {
                try await bestSearchLyrics(for: track, query: .text("\(track.artist) \(track.title)"))
            }
        ])

        if let payload = summary.payload {
            return payload
        }

        if summary.hadFailure {
            throw LRCLIBError.lookupFailed
        }

        return .missing
    }

    private func delayedLookup(
        _ lookup: @escaping @Sendable () async throws -> LRCLIBRecord?
    ) -> @Sendable () async throws -> LRCLIBRecord? {
        { [fallbackDelayNanoseconds] in
            if fallbackDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: fallbackDelayNanoseconds)
            }
            return try await lookup()
        }
    }

    private func firstRenderablePayload(
        from lookups: [@Sendable () async throws -> LRCLIBRecord?]
    ) async -> LookupSummary {
        await withTaskGroup(of: LookupOutcome.self, returning: LookupSummary.self) { group in
            for lookup in lookups {
                group.addTask {
                    do {
                        guard let record = try await lookup() else {
                            return .missing
                        }
                        let payload = payload(from: record)
                        return payload.hasRenderableContent ? .found(payload) : .missing
                    } catch {
                        return .failed
                    }
                }
            }

            var summary = LookupSummary()
            for await outcome in group {
                switch outcome {
                case .found(let candidate):
                    group.cancelAll()
                    return LookupSummary(payload: candidate, hadFailure: summary.hadFailure)
                case .missing:
                    continue
                case .failed:
                    summary.hadFailure = true
                }
            }

            return summary
        }
    }

    private func exactLyrics(for track: TrackInfo, includesAlbum: Bool) async throws -> LRCLIBRecord? {
        var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "duration", value: "\(max(1, track.durationMilliseconds / 1000))")
        ]
        if includesAlbum {
            queryItems.append(URLQueryItem(name: "album_name", value: track.album ?? ""))
        }
        components.queryItems = queryItems

        let (data, response) = try await session.data(for: request(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw LRCLIBError.invalidResponse
        }

        if http.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(http.statusCode) else {
            throw LRCLIBError.requestFailed(http.statusCode)
        }

        return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
    }

    private func bestSearchLyrics(for track: TrackInfo, query: SearchQuery) async throws -> LRCLIBRecord? {
        let records = try await searchLyrics(for: track, query: query)
        return records
            .sorted { lhs, rhs in
                score(record: lhs, for: track) > score(record: rhs, for: track)
            }
            .first
    }

    private func searchLyrics(for track: TrackInfo, query: SearchQuery) async throws -> [LRCLIBRecord] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        switch query {
        case .fields:
            components.queryItems = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title)
            ]
        case .text(let value):
            components.queryItems = [
                URLQueryItem(name: "q", value: value)
            ]
        }

        let (data, response) = try await session.data(for: request(url: components.url!))
        guard let http = response as? HTTPURLResponse else {
            throw LRCLIBError.invalidResponse
        }

        if http.statusCode == 404 {
            return []
        }

        guard (200..<300).contains(http.statusCode) else {
            throw LRCLIBError.requestFailed(http.statusCode)
        }

        return try JSONDecoder().decode([LRCLIBRecord].self, from: data)
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("UltraDolmengSpotifyLyric/0.1 (macOS personal lyrics overlay)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func score(record: LRCLIBRecord, for track: TrackInfo) -> Int {
        var score = 0
        if normalized(record.trackName) == normalized(track.title) {
            score += 80
        }
        if normalized(record.artistName) == normalized(track.artist) {
            score += 50
        } else if normalized(track.artist).contains(normalized(record.artistName)) ||
                    normalized(record.artistName).contains(normalized(track.artist)) {
            score += 24
        }
        if normalized(record.albumName) == normalized(track.album) {
            score += 20
        }
        if let duration = record.duration {
            let target = Double(track.durationMilliseconds) / 1000
            score += max(0, 18 - Int(abs(duration - target)))
        }
        if let syncedLyrics = record.syncedLyrics,
           syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 12
        }
        if let plainLyrics = record.plainLyrics,
           plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 6
        }
        return score
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

    private static func makeFastSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }
}

private enum SearchQuery {
    case fields
    case text(String)
}

private enum LookupOutcome {
    case found(LyricsPayload)
    case missing
    case failed
}

private struct LookupSummary {
    var payload: LyricsPayload?
    var hadFailure = false
}

private extension LyricsPayload {
    var hasRenderableContent: Bool {
        switch self {
        case .synced(let lines):
            return lines.isEmpty == false
        case .plain(let lines):
            return lines.isEmpty == false
        case .missing:
            return false
        }
    }
}

enum LRCLIBError: LocalizedError {
    case invalidResponse
    case requestFailed(Int)
    case lookupFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "LRCLIB 응답을 읽지 못했어."
        case .requestFailed(let status):
            return "LRCLIB request failed: \(status)"
        case .lookupFailed:
            return "LRCLIB 가사 조회가 지연되거나 실패했어."
        }
    }
}
