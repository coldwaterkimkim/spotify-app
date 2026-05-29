import Combine
import Foundation

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var displayState: PlaybackDisplayState = .disconnected
    @Published private(set) var caption = CaptionLines.empty
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Spotify 연결이 필요해"
    @Published var demoMode = false

    private let settings: AppSettings
    private let authService: SpotifyAuthService
    private let spotifyClient: SpotifyAPIClient
    private let lrclibClient: LRCLIBClient
    private var pollingTimer: Timer?
    private var captionTimer: Timer?
    private var hideTask: Task<Void, Never>?
    private var currentTrack: TrackInfo?
    private var currentLyrics: LyricsPayload = .missing
    private var lastSpotifyPoll = Date.distantPast

    init(
        settings: AppSettings,
        authService: SpotifyAuthService? = nil,
        spotifyClient: SpotifyAPIClient = SpotifyAPIClient(),
        lrclibClient: LRCLIBClient = LRCLIBClient()
    ) {
        self.settings = settings
        self.authService = authService ?? SpotifyAuthService()
        self.spotifyClient = spotifyClient
        self.lrclibClient = lrclibClient
    }

    func start() {
        isConnected = authService.storedToken() != nil
        displayState = isConnected ? .idle : .disconnected
        startTimers()
    }

    func stop() {
        pollingTimer?.invalidate()
        captionTimer?.invalidate()
        pollingTimer = nil
        captionTimer = nil
    }

    func connectSpotify() {
        statusText = "Spotify 로그인 여는 중"
        Task {
            do {
                _ = try await authService.connect(clientID: settings.spotifyClientID)
                isConnected = true
                demoMode = false
                displayState = .idle
                statusText = "Spotify 연결됨"
                await pollSpotify(force: true)
            } catch {
                statusText = error.localizedDescription
                displayState = .error(error.localizedDescription)
            }
        }
    }

    func disconnectSpotify() {
        Task {
            try? authService.clearStoredToken()
            isConnected = false
            currentTrack = nil
            currentLyrics = .missing
            caption = .empty
            demoMode = false
            displayState = .disconnected
            statusText = "Spotify 연결이 해제됐어"
        }
    }

    func showDemoOverlay() {
        demoMode = true
        isConnected = authService.storedToken() != nil
        let demoTrack = TrackInfo(
            id: "demo",
            title: "Caption Preview",
            artist: "울트라돌멩",
            album: "Preview",
            durationMilliseconds: 240_000,
            progressMilliseconds: 0,
            isPlaying: true,
            capturedAt: Date()
        )
        currentTrack = demoTrack
        currentLyrics = .synced([
            LyricsLine(time: 0, text: "I've been trying to call"),
            LyricsLine(time: 4.2, text: "I've been on my own for long enough"),
            LyricsLine(time: 9.1, text: "Maybe you can show me how to love"),
            LyricsLine(time: 14.5, text: "Maybe")
        ])
        displayState = .playing(demoTrack)
        statusText = "미리보기 재생 중"
        updateCaption()
    }

    func hideDemoOverlay() {
        demoMode = false
        currentTrack = nil
        currentLyrics = .missing
        caption = .empty
        displayState = isConnected ? .idle : .disconnected
        statusText = isConnected ? "Spotify 연결됨" : "Spotify 연결이 필요해"
    }

    private func startTimers() {
        pollingTimer?.invalidate()
        captionTimer?.invalidate()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollSpotify()
            }
        }

        captionTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCaption()
            }
        }
    }

    private func pollSpotify(force: Bool = false) async {
        guard demoMode == false else { return }
        guard isConnected else { return }
        guard force || Date().timeIntervalSince(lastSpotifyPoll) > 1.2 else { return }
        lastSpotifyPoll = Date()

        do {
            guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                isConnected = false
                displayState = .disconnected
                statusText = "Spotify 연결이 필요해"
                return
            }

            let track = try await spotifyClient.currentPlayback(accessToken: token)
            guard let track else {
                currentTrack = nil
                currentLyrics = .missing
                caption = .empty
                displayState = .idle
                statusText = "재생 중인 음악 없음"
                return
            }

            if currentTrack?.id != track.id {
                hideTask?.cancel()
                currentTrack = track
                currentLyrics = .missing
                caption = CaptionLines(current: "Lyrics loading", next: nil, isFallback: true)
                statusText = "가사 찾는 중: \(track.displayTitle)"
                Task {
                    await loadLyrics(for: track)
                }
            } else {
                currentTrack = track
            }

            if track.isPlaying {
                hideTask?.cancel()
                displayState = .playing(track)
            } else {
                displayState = .paused(track)
                schedulePauseClear()
            }
        } catch {
            statusText = error.localizedDescription
            displayState = .error(error.localizedDescription)
        }
    }

    private func loadLyrics(for track: TrackInfo) async {
        do {
            var lyrics = try await lrclibClient.lyrics(for: track)
            if case .plain = lyrics, settings.showPlainLyricsFallback == false {
                lyrics = .missing
            }
            guard currentTrack?.id == track.id else { return }
            currentLyrics = lyrics
            switch lyrics {
            case .synced:
                statusText = "싱크 가사 표시 중"
            case .plain:
                statusText = "싱크 없는 원문 가사 표시 중"
            case .missing:
                statusText = "가사를 찾지 못했어"
                caption = CaptionLines(current: "Lyrics not found", next: nil, isFallback: true)
                schedulePauseClear(delay: 2.2)
            }
        } catch {
            guard currentTrack?.id == track.id else { return }
            statusText = error.localizedDescription
            caption = CaptionLines(current: "Lyrics unavailable", next: nil, isFallback: true)
            schedulePauseClear(delay: 2.2)
        }
    }

    private func updateCaption() {
        guard let track = currentTrack else {
            caption = .empty
            return
        }

        guard track.isPlaying || demoMode else {
            return
        }

        let elapsed = Date().timeIntervalSince(track.capturedAt)
        let progress = Double(track.progressMilliseconds) / 1000 + elapsed
        let updated = LyricsParser.caption(
            for: currentLyrics,
            progress: progress,
            offset: settings.lyricsOffset
        )

        if updated.current.isEmpty == false {
            caption = updated
        }
    }

    private func schedulePauseClear(delay: Double? = nil) {
        hideTask?.cancel()
        let fadeDelay = delay ?? settings.pauseFadeDelay
        hideTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0.2, fadeDelay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard self?.demoMode == false else { return }
                self?.caption = .empty
                self?.currentTrack = nil
                self?.currentLyrics = .missing
            }
        }
    }
}
