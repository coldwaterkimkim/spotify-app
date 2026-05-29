import Foundation

struct SpotifyAPIClient {
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

        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown Spotify API error"
            throw SpotifyAPIError.requestFailed(http.statusCode, text)
        }

        let playback = try JSONDecoder().decode(SpotifyPlaybackResponse.self, from: data)
        return playback.trackInfo()
    }
}

enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Spotify 응답을 읽지 못했어."
        case .requestFailed(let status, let message):
            return "Spotify API error \(status): \(message)"
        }
    }
}
