import Foundation
import Network

@MainActor
final class LoopbackOAuthServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, Error>?
    private let callbackPort: UInt16 = 43879

    struct Callback {
        let code: String
        let state: String
    }

    func start() async throws -> (redirectURI: String, callback: Task<Callback, Error>) {
        guard let port = NWEndpoint.Port(rawValue: callbackPort) else {
            throw OAuthServerError.missingPort
        }

        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                await self?.handle(connection)
            }
        }
        listener.start(queue: .main)
        self.listener = listener

        let task = Task<Callback, Error> {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        return ("http://127.0.0.1:\(callbackPort)/callback", task)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        continuation = nil
    }

    private func handle(_ connection: NWConnection) async {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let data, let request = String(data: data, encoding: .utf8) else {
                    self.sendResponse(connection, status: "400 Bad Request", body: "Bad request")
                    return
                }

                guard let firstLine = request.components(separatedBy: "\r\n").first,
                      let path = firstLine.components(separatedBy: " ").dropFirst().first,
                      let url = URL(string: "http://127.0.0.1\(path)"),
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    self.sendResponse(connection, status: "400 Bad Request", body: "Bad request")
                    return
                }

                let items = components.queryItems ?? []
                if let error = items.first(where: { $0.name == "error" })?.value {
                    self.continuation?.resume(throwing: OAuthServerError.spotify(error))
                    self.sendResponse(connection, status: "200 OK", body: "Spotify authorization failed. You can close this window.")
                    self.stop()
                    return
                }

                guard let code = items.first(where: { $0.name == "code" })?.value,
                      let state = items.first(where: { $0.name == "state" })?.value else {
                    self.sendResponse(connection, status: "400 Bad Request", body: "Missing authorization code")
                    return
                }

                self.continuation?.resume(returning: Callback(code: code, state: state))
                self.sendResponse(connection, status: "200 OK", body: "Spotify connected. You can close this window and return to 울트라돌멩의솦티파이리릭.")
                self.stop()
            }
        }
    }

    private func sendResponse(_ connection: NWConnection, status: String, body: String) {
        let html = """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"><title>Spotify Connected</title></head>
          <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;">
            <h2>\(body)</h2>
          </body>
        </html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum OAuthServerError: LocalizedError {
    case missingPort
    case spotify(String)

    var errorDescription: String? {
        switch self {
        case .missingPort:
            return "Could not open a local callback port."
        case .spotify(let error):
            return "Spotify authorization failed: \(error)"
        }
    }
}
