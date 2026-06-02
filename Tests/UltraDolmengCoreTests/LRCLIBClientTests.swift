import XCTest
@testable import UltraDolmengCore

final class LRCLIBClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testReturnsSearchResultWhenExactLookupFails() async throws {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/get") {
                return response(status: 500, url: url, body: "{}")
            }

            return response(status: 200, url: url, body: """
            [
              {
                "trackName": "Next Level",
                "artistName": "E Sens",
                "albumName": "The Anecdote",
                "duration": 214,
                "plainLyrics": "first\\nsecond",
                "syncedLyrics": "[00:01.00]first\\n[00:02.00]second"
              }
            ]
            """)
        }

        let client = LRCLIBClient(session: mockSession(), fallbackDelayNanoseconds: 0)
        let lyrics = try await client.lyrics(for: nextLevelTrack)

        guard case .synced(let lines) = lyrics else {
            return XCTFail("Expected synced lyrics")
        }
        XCTAssertEqual(lines.map(\.text), ["first", "second"])
    }

    func testUsesTextQueryFallbackWhenFieldSearchMisses() async throws {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/get") {
                return response(status: 404, url: url, body: "{}")
            }

            let hasTextQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains { $0.name == "q" } ?? false

            if hasTextQuery {
                return response(status: 200, url: url, body: """
                [
                  {
                    "trackName": "Next Level",
                    "artistName": "E Sens",
                    "albumName": "The Anecdote",
                    "duration": 214,
                    "plainLyrics": "fallback line",
                    "syncedLyrics": null
                  }
                ]
                """)
            }

            return response(status: 200, url: url, body: "[]")
        }

        let client = LRCLIBClient(session: mockSession(), fallbackDelayNanoseconds: 0)
        let lyrics = try await client.lyrics(for: nextLevelTrack)

        XCTAssertEqual(lyrics, .plain(["fallback line"]))
    }

    func testThrowsWhenProviderFailsInsteadOfReportingMissing() async {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            return response(status: 503, url: url, body: "{}")
        }

        let client = LRCLIBClient(session: mockSession(), fallbackDelayNanoseconds: 0)

        do {
            _ = try await client.lyrics(for: nextLevelTrack)
            XCTFail("Expected LRCLIB lookup to throw")
        } catch LRCLIBError.lookupFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private var nextLevelTrack: TrackInfo {
        TrackInfo(
            id: "6evOSyirpE2XulH7rvrLFK",
            title: "Next Level",
            artist: "E SENS",
            album: "The Anecdote",
            durationMilliseconds: 213_793,
            progressMilliseconds: 0,
            isPlaying: true,
            capturedAt: Date()
        )
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func response(status: Int, url: URL, body: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}
