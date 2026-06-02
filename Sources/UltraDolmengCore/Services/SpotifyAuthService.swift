import AppKit
import Foundation

struct SpotifyToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var needsRefresh: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }
}

@MainActor
final class SpotifyAuthService {
    private let keychain = KeychainStore()
    private let callbackServer = LoopbackOAuthServer()
    private let tokenAccount = "spotifyToken"
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private let scopes = "user-read-currently-playing user-read-playback-state user-modify-playback-state user-library-read"

    func storedToken() -> SpotifyToken? {
        do {
            guard let encoded = try keychain.load(account: tokenAccount),
                  let data = encoded.data(using: .utf8) else {
                return nil
            }
            return try JSONDecoder().decode(SpotifyToken.self, from: data)
        } catch {
            return nil
        }
    }

    func clearStoredToken() throws {
        try keychain.delete(account: tokenAccount)
    }

    func connect(clientID: String) async throws -> SpotifyToken {
        let cleanClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanClientID.isEmpty == false else {
            throw SpotifyAuthError.missingClientID
        }

        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.makeChallenge(for: verifier)
        let state = PKCE.makeState()
        let server = try await callbackServer.start()

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: cleanClientID),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw SpotifyAuthError.invalidAuthorizationURL
        }

        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        let callback = try await server.callback.value
        guard callback.state == state else {
            throw SpotifyAuthError.stateMismatch
        }

        let response = try await exchangeCode(
            callback.code,
            verifier: verifier,
            redirectURI: server.redirectURI,
            clientID: cleanClientID
        )
        let token = SpotifyToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        try save(token)
        return token
    }

    func validAccessToken(clientID: String) async throws -> String? {
        guard let token = storedToken() else {
            return nil
        }

        if token.needsRefresh {
            let refreshed = try await refresh(token: token, clientID: clientID)
            return refreshed.accessToken
        }

        return token.accessToken
    }

    private func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: String,
        clientID: String
    ) async throws -> SpotifyTokenResponse {
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ]

        return try await tokenRequest(body: body)
    }

    private func refresh(token: SpotifyToken, clientID: String) async throws -> SpotifyToken {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
            "client_id": clientID
        ]

        let response = try await tokenRequest(body: body)
        let refreshed = SpotifyToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        try save(refreshed)
        return refreshed
    }

    private func tokenRequest(body: [String: String]) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.formURLEncodedData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown token error"
            throw SpotifyAuthError.tokenExchangeFailed(text)
        }

        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private func save(_ token: SpotifyToken) throws {
        let data = try JSONEncoder().encode(token)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw SpotifyAuthError.tokenEncodingFailed
        }
        try keychain.save(encoded, account: tokenAccount)
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum SpotifyAuthError: LocalizedError {
    case missingClientID
    case invalidAuthorizationURL
    case stateMismatch
    case tokenExchangeFailed(String)
    case tokenEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Spotify Client ID를 먼저 입력해야 해."
        case .invalidAuthorizationURL:
            return "Spotify 로그인 URL을 만들지 못했어."
        case .stateMismatch:
            return "Spotify 로그인 응답 검증에 실패했어."
        case .tokenExchangeFailed(let message):
            return "Spotify token exchange failed: \(message)"
        case .tokenEncodingFailed:
            return "Spotify token 저장에 실패했어."
        }
    }
}
