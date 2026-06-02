import Foundation

struct SpotifyLocalPlaybackClient {
    func currentPlayback() async throws -> TrackInfo? {
        let script = """
        tell application "System Events"
          set spotifyRunning to exists process "Spotify"
        end tell
        if spotifyRunning is false then
          return "not_running"
        end if
        tell application "Spotify"
          if player state is stopped then
            return "stopped"
          end if
          set trackState to player state as text
          set trackName to name of current track
          set trackArtist to artist of current track
          set trackAlbum to album of current track
          set trackDuration to duration of current track
          set trackPosition to player position
          set trackURL to spotify url of current track
          return trackState & linefeed & trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & trackDuration & linefeed & trackPosition & linefeed & trackURL
        end tell
        """

        let output = try await runAppleScript(script)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if output == "not_running" || output == "stopped" || output.isEmpty {
            return nil
        }

        let lines = output.components(separatedBy: .newlines)
        guard lines.count >= 6 else {
            throw SpotifyLocalPlaybackError.invalidOutput
        }

        let state = lines[0]
        let title = lines[1]
        let artist = lines[2]
        let album = lines[3].isEmpty ? nil : lines[3]
        let durationMilliseconds = Int(Double(lines[4]) ?? 0)
        let progressMilliseconds = Int((Double(lines[5]) ?? 0) * 1000)
        let spotifyURL = lines.count >= 7 ? lines[6] : ""

        return TrackInfo(
            id: spotifyURL.isEmpty ? "\(title)-\(artist)" : spotifyURL,
            title: title,
            artist: artist,
            album: album,
            durationMilliseconds: max(durationMilliseconds, 1),
            progressMilliseconds: max(progressMilliseconds, 0),
            isPlaying: state == "playing",
            capturedAt: Date()
        )
    }

    private func runAppleScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let output = String(
                    data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let error = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: SpotifyLocalPlaybackError.scriptFailed(error))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum SpotifyLocalPlaybackError: LocalizedError {
    case invalidOutput
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "Spotify 로컬 앱 재생 정보를 읽지 못했어."
        case .scriptFailed(let message):
            return message.isEmpty ? "Spotify 로컬 앱 접근에 실패했어." : message
        }
    }
}
