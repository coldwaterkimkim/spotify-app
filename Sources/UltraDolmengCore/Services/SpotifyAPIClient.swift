import Foundation

struct SpotifyAPIClient {
    private let decoder = JSONDecoder()

    func currentPlayback(accessToken: String) async throws -> TrackInfo? {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/currently-playing")!
        components.queryItems = [
            URLQueryItem(name: "additional_types", value: "track")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }

        if http.statusCode == 204 {
            return nil
        }

        try validate(data: data, http: http)

        let playback = try decoder.decode(SpotifyPlaybackResponse.self, from: data)
        return playback.trackInfo()
    }

    func queue(accessToken: String) async throws -> [QueueItemInfo] {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }

        if http.statusCode == 204 {
            return []
        }

        try validate(data: data, http: http)

        let queue = try decoder.decode(SpotifyQueueResponse.self, from: data)
        return queue.queueItems()
    }

    func resume(accessToken: String) async throws {
        try await sendPlaybackCommand(
            accessToken: accessToken,
            method: "PUT",
            path: "play"
        )
    }

    func pause(accessToken: String) async throws {
        try await sendPlaybackCommand(
            accessToken: accessToken,
            method: "PUT",
            path: "pause"
        )
    }

    func skipToNext(accessToken: String) async throws {
        try await sendPlaybackCommand(
            accessToken: accessToken,
            method: "POST",
            path: "next"
        )
    }

    func skipToPrevious(accessToken: String) async throws {
        try await sendPlaybackCommand(
            accessToken: accessToken,
            method: "POST",
            path: "previous"
        )
    }

    private func sendPlaybackCommand(accessToken: String, method: String, path: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }

        try validate(data: data, http: http)
    }

    private func validate(data: Data, http: HTTPURLResponse) throws {
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw SpotifyAPIError.rateLimited(retryAfter: retryAfterSeconds(from: http))
            }

            let text = String(data: data, encoding: .utf8) ?? "Unknown Spotify API error"
            throw SpotifyAPIError.requestFailed(http.statusCode, text)
        }
    }

    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let seconds = TimeInterval(rawValue) else {
            return 30
        }

        return max(1, seconds)
    }
}

enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Spotify 응답을 읽지 못했어."
        case .rateLimited(let retryAfter):
            return "Spotify 요청 제한 중이야. \(Int(ceil(retryAfter)))초 후 다시 시도할게."
        case .requestFailed(let status, let message):
            return "Spotify API error \(status): \(message)"
        }
    }
}
