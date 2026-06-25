import Combine
import Foundation

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var displayState: PlaybackDisplayState = .disconnected
    @Published private(set) var caption = CaptionLines.empty
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Spotify 연결이 필요해"
    @Published private(set) var queueItems: [QueueItemInfo] = []
    @Published private(set) var isQueueLoading = false
    @Published private(set) var queueStatusText: String?
    @Published var demoMode = false

    var isPlaybackActive: Bool {
        if case .playing = displayState {
            return true
        }
        return false
    }

    var shouldShowCaptionOverlay: Bool {
        caption.current.isEmpty == false || isPlaybackActive
    }

    private let settings: AppSettings
    private let authService: SpotifyAuthService
    private let spotifyClient: SpotifyAPIClient
    private let localPlaybackClient: SpotifyLocalPlaybackClient
    private let lrclibClient: LRCLIBClient
    private let lyricsDiskCache: LyricsDiskCache
    private var pollingTimer: Timer?
    private var captionTimer: Timer?
    private var hideTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var queuePrefetchTask: Task<Void, Never>?
    private var lyricsPrefetchTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var lyricsRetryTask: Task<Void, Never>?
    private var currentTrack: TrackInfo?
    private var currentLyrics: LyricsPayload = .missing
    private var lyricsCache: [LyricsCacheKey: LyricsPayload] = [:]
    private var lyricsRequests: [LyricsCacheKey: Task<LyricsPayload, Error>] = [:]
    private var lastSpotifyPoll = Date.distantPast
    private var lastQueuePoll = Date.distantPast
    private var spotifyRateLimitedUntil: Date?

    init(
        settings: AppSettings,
        authService: SpotifyAuthService? = nil,
        spotifyClient: SpotifyAPIClient = SpotifyAPIClient(),
        localPlaybackClient: SpotifyLocalPlaybackClient = SpotifyLocalPlaybackClient(),
        lrclibClient: LRCLIBClient = LRCLIBClient(),
        lyricsDiskCache: LyricsDiskCache = LyricsDiskCache()
    ) {
        self.settings = settings
        self.authService = authService ?? SpotifyAuthService()
        self.spotifyClient = spotifyClient
        self.localPlaybackClient = localPlaybackClient
        self.lrclibClient = lrclibClient
        self.lyricsDiskCache = lyricsDiskCache
    }

    func start(loadStoredToken: Bool = true) {
        isConnected = loadStoredToken && authService.storedToken() != nil
        displayState = isConnected ? .idle : .disconnected
        startTimers()
    }

    func stop() {
        pollingTimer?.invalidate()
        captionTimer?.invalidate()
        queueTask?.cancel()
        queuePrefetchTask?.cancel()
        lyricsPrefetchTask?.cancel()
        lyricsTask?.cancel()
        lyricsRetryTask?.cancel()
        lyricsRequests.values.forEach { $0.cancel() }
        pollingTimer = nil
        captionTimer = nil
        queueTask = nil
        queuePrefetchTask = nil
        lyricsPrefetchTask = nil
        lyricsTask = nil
        lyricsRetryTask = nil
        lyricsRequests = [:]
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
            queueTask?.cancel()
            queuePrefetchTask?.cancel()
            lyricsPrefetchTask?.cancel()
            lyricsTask?.cancel()
            lyricsRetryTask?.cancel()
            queueItems = []
            queueStatusText = nil
            isQueueLoading = false
            caption = .empty
            demoMode = false
            displayState = .disconnected
            statusText = "Spotify 연결이 해제됐어"
        }
    }

    func showDemoOverlay() {
        demoMode = true
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
        queueItems = demoQueueItems
        queueStatusText = nil
        isQueueLoading = false
        updateCaption()
    }

    func hideDemoOverlay() {
        demoMode = false
        currentTrack = nil
        currentLyrics = .missing
        queuePrefetchTask?.cancel()
        lyricsPrefetchTask?.cancel()
        lyricsTask?.cancel()
        lyricsRetryTask?.cancel()
        queueItems = []
        queueStatusText = nil
        isQueueLoading = false
        caption = .empty
        displayState = isConnected ? .idle : .disconnected
        statusText = isConnected ? "Spotify 연결됨" : "Spotify 연결이 필요해"
    }

    func refreshQueue(force: Bool = false, showsLoading: Bool = true) {
        if demoMode {
            queueItems = demoQueueItems
            queueStatusText = nil
            isQueueLoading = false
            return
        }

        guard isConnected else {
            queueItems = []
            queueStatusText = "Spotify 연결 필요"
            isQueueLoading = false
            return
        }

        guard currentTrack != nil else {
            queueItems = []
            queueStatusText = "재생 중인 음악 없음"
            isQueueLoading = false
            return
        }

        if force == false,
           Date().timeIntervalSince(lastQueuePoll) < 4,
           (queueItems.isEmpty == false || queueStatusText != nil) {
            return
        }

        lastQueuePoll = Date()
        queueTask?.cancel()
        if showsLoading {
            isQueueLoading = true
            queueStatusText = nil
        }

        queueTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                    guard Task.isCancelled == false else { return }
                    isConnected = false
                    if showsLoading {
                        queueItems = []
                        queueStatusText = "Spotify 연결 필요"
                    }
                    isQueueLoading = false
                    return
                }

                let items = try await spotifyClient.queue(accessToken: token)
                guard Task.isCancelled == false else { return }
                let visibleItems = Array(items.prefix(50))
                queueItems = visibleItems
                queueStatusText = items.isEmpty ? "다음 곡 없음" : nil
                isQueueLoading = false
                prefetchLyrics(for: Array(visibleItems.prefix(3)))
            } catch SpotifyAPIError.rateLimited(let retryAfter) {
                guard Task.isCancelled == false else { return }
                applySpotifyRateLimit(retryAfter, reason: "queue 조회")
                if showsLoading {
                    queueStatusText = "Spotify 요청 제한"
                }
                isQueueLoading = false
            } catch {
                guard Task.isCancelled == false else { return }
                if showsLoading {
                    queueItems = []
                    queueStatusText = "재생목록을 못 읽었어"
                }
                isQueueLoading = false
            }
        }
    }

    func skipToQueueItem(at index: Int) {
        if demoMode {
            guard queueItems.indices.contains(index) else { return }
            let item = queueItems[index]
            applyDemoQueueSelection(item, statusPrefix: "미리보기 queue 선택")
            queueItems.removeFirst(index + 1)
            return
        }

        guard queueItems.indices.contains(index) else { return }
        prefetchLyrics(for: [queueItems[index]])

        queueTask?.cancel()
        queueItems.removeFirst(index + 1)
        queueStatusText = queueItems.isEmpty ? "다음 곡 없음" : nil
        isQueueLoading = false

        queueTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                    guard Task.isCancelled == false else { return }
                    isConnected = false
                    queueStatusText = "Spotify 연결 필요"
                    return
                }

                for step in 0...index {
                    try await spotifyClient.skipToNext(accessToken: token)
                    if step < index {
                        try await Task.sleep(nanoseconds: 220_000_000)
                    }
                }
                guard Task.isCancelled == false else { return }
                if queueItems.isEmpty == false {
                    queueStatusText = nil
                }
                lastQueuePoll = .distantPast
                await pollSpotify(force: true, preservesVisibleQueue: true)
            } catch SpotifyAPIError.requestFailed(let status, _) where status == 403 {
                guard Task.isCancelled == false else { return }
                queueStatusText = "Spotify 다시 연결 필요"
                statusText = "queue 클릭 재생 권한을 받으려면 Spotify를 다시 연결해야 해"
            } catch SpotifyAPIError.rateLimited(let retryAfter) {
                guard Task.isCancelled == false else { return }
                applySpotifyRateLimit(retryAfter, reason: "queue 클릭 재생")
                queueStatusText = "Spotify 요청 제한"
            } catch {
                guard Task.isCancelled == false else { return }
                queueStatusText = "재생 전환 실패"
                statusText = error.localizedDescription
            }
        }
    }

    func skipToPrevious() {
        if demoMode {
            statusText = "미리보기 이전 곡"
            return
        }

        runPlaybackCommand(status: "이전 곡으로 이동 중") { token in
            try await self.spotifyClient.skipToPrevious(accessToken: token)
        }
    }

    func skipToNext() {
        if demoMode {
            statusText = "미리보기 다음 곡"
            guard queueItems.isEmpty == false else { return }
            let item = queueItems.removeFirst()
            applyDemoQueueSelection(item, statusPrefix: "미리보기 다음 곡")
            return
        }

        if let nextItem = queueItems.first {
            prefetchLyrics(for: [nextItem])
        }

        runPlaybackCommand(status: "다음 곡으로 이동 중") { token in
            try await self.spotifyClient.skipToNext(accessToken: token)
        }
    }

    func togglePlayPause() {
        if demoMode {
            statusText = isPlaybackActive ? "미리보기 일시정지" : "미리보기 재생"
            if let currentTrack {
                displayState = isPlaybackActive ? .paused(currentTrack) : .playing(currentTrack)
            }
            return
        }

        let shouldPause = isPlaybackActive
        runPlaybackCommand(status: shouldPause ? "일시정지 중" : "재생 재개 중") { token in
            if shouldPause {
                try await self.spotifyClient.pause(accessToken: token)
            } else {
                try await self.spotifyClient.resume(accessToken: token)
            }
        }
    }

    private func runPlaybackCommand(
        status: String,
        command: @escaping (String) async throws -> Void
    ) {
        queueTask?.cancel()
        statusText = status

        queueTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                    guard Task.isCancelled == false else { return }
                    isConnected = false
                    queueStatusText = "Spotify 연결 필요"
                    return
                }

                try await command(token)
                guard Task.isCancelled == false else { return }
                queueStatusText = nil
                await pollSpotify(force: true)
                refreshQueue(force: true, showsLoading: false)
            } catch SpotifyAPIError.requestFailed(let status, _) where status == 403 {
                guard Task.isCancelled == false else { return }
                queueStatusText = "Spotify 다시 연결 필요"
                statusText = "재생 제어 권한을 받으려면 Spotify를 다시 연결해야 해"
            } catch SpotifyAPIError.rateLimited(let retryAfter) {
                guard Task.isCancelled == false else { return }
                applySpotifyRateLimit(retryAfter, reason: "재생 제어")
                queueStatusText = "Spotify 요청 제한"
            } catch {
                guard Task.isCancelled == false else { return }
                queueStatusText = "재생 제어 실패"
                statusText = error.localizedDescription
            }
        }
    }

    private func startTimers() {
        pollingTimer?.invalidate()
        captionTimer?.invalidate()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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

    private func pollSpotify(force: Bool = false, preservesVisibleQueue: Bool = false) async {
        guard demoMode == false else { return }
        guard isConnected else { return }
        if let remaining = spotifyRateLimitRemaining() {
            statusText = "Spotify 요청 제한 · \(Int(ceil(remaining)))초 쉬는 중"
            _ = await pollLocalSpotifyFallback(preservesVisibleQueue: preservesVisibleQueue)
            return
        }

        guard force || Date().timeIntervalSince(lastSpotifyPoll) > 1.75 else { return }
        lastSpotifyPoll = Date()

        do {
            guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                isConnected = false
                displayState = .disconnected
                statusText = "Spotify 연결이 필요해"
                return
            }

            let track = try await spotifyClient.currentPlayback(accessToken: token)
            applyPlaybackTrack(
                track,
                preservesVisibleQueue: preservesVisibleQueue,
                allowsQueuePrefetch: true,
                statusPrefix: nil
            )
        } catch SpotifyAPIError.rateLimited(let retryAfter) {
            applySpotifyRateLimit(retryAfter, reason: "재생 상태 확인")
            _ = await pollLocalSpotifyFallback(preservesVisibleQueue: preservesVisibleQueue)
        } catch {
            statusText = error.localizedDescription
            displayState = .error(error.localizedDescription)
        }
    }

    private func pollLocalSpotifyFallback(preservesVisibleQueue: Bool) async -> Bool {
        do {
            let track = try await localPlaybackClient.currentPlayback()
            applyPlaybackTrack(
                track,
                preservesVisibleQueue: preservesVisibleQueue,
                allowsQueuePrefetch: false,
                statusPrefix: "Spotify API 제한 중 · 로컬 앱으로 표시"
            )
            return track != nil
        } catch {
            if currentTrack != nil {
                return false
            }

            statusText = "Spotify API 제한 중 · 로컬 앱 접근 필요"
            return false
        }
    }

    private func applyPlaybackTrack(
        _ track: TrackInfo?,
        preservesVisibleQueue: Bool,
        allowsQueuePrefetch: Bool,
        statusPrefix: String?
    ) {
        guard let track else {
            currentTrack = nil
            currentLyrics = .missing
            queueItems = []
            queueStatusText = nil
            lastQueuePoll = .distantPast
            caption = .empty
            displayState = .idle
            statusText = statusPrefix ?? "재생 중인 음악 없음"
            return
        }

        if currentTrack?.id != track.id {
            hideTask?.cancel()
            lyricsTask?.cancel()
            lyricsRetryTask?.cancel()
            currentTrack = track
            if preservesVisibleQueue == false {
                queueItems = []
                queueStatusText = nil
            }
            lastQueuePoll = .distantPast
            prepareLyrics(for: track)
            if allowsQueuePrefetch {
                prefetchUpcomingLyrics()
            }
        } else {
            currentTrack = track
        }

        if track.isPlaying {
            hideTask?.cancel()
            displayState = .playing(track)
            if let statusPrefix {
                statusText = statusPrefix
            }
        } else {
            displayState = .paused(track)
            schedulePauseClear()
        }
    }

    private func prepareLyrics(for track: TrackInfo) {
        let key = LyricsCacheKey(track: track)
        if let cached = lyricsCache[key] {
            applyLyrics(cached)
            return
        }

        if let cached = lyricsDiskCache.lyrics(for: key) {
            lyricsCache[key] = cached
            applyLyrics(cached)
            return
        }

        currentLyrics = .missing
        caption = .empty
        statusText = "가사 준비 중: \(track.displayTitle)"
        lyricsTask = Task { [weak self] in
            await self?.loadLyrics(for: track, attempt: 0)
        }
    }

    private func loadLyrics(for track: TrackInfo, attempt: Int) async {
        do {
            let rawLyrics = try await cachedLyrics(for: track)
            guard Task.isCancelled == false, currentTrack?.id == track.id else { return }

            applyLyrics(rawLyrics)
        } catch {
            guard Task.isCancelled == false, currentTrack?.id == track.id else { return }
            statusText = error.localizedDescription
            caption = CaptionLines(current: "Lyrics unavailable", next: nil, isFallback: true)
            scheduleLyricsRetry(for: track, nextAttempt: attempt + 1)
        }
    }

    private func scheduleLyricsRetry(for track: TrackInfo, nextAttempt: Int) {
        guard nextAttempt <= 2 else { return }

        lyricsRetryTask?.cancel()
        lyricsRetryTask = Task { [weak self] in
            let seconds = nextAttempt == 1 ? 5.0 : 15.0
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run {
                guard self?.currentTrack?.id == track.id, self?.demoMode == false else { return }
                self?.lyricsTask?.cancel()
                self?.lyricsTask = Task { [weak self] in
                    await self?.loadLyrics(for: track, attempt: nextAttempt)
                }
            }
        }
    }

    private func applyLyrics(_ rawLyrics: LyricsPayload) {
        caption = .empty
        let lyrics = displayableLyrics(rawLyrics)
        currentLyrics = lyrics
        statusText = statusText(for: lyrics)
        switch lyrics {
        case .synced, .plain:
            updateCaption()
        case .missing:
            caption = CaptionLines(current: "Lyrics not found", next: nil, isFallback: true)
        }
    }

    private func prefetchUpcomingLyrics() {
        guard demoMode == false, isConnected else { return }

        queuePrefetchTask?.cancel()
        queuePrefetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                    return
                }

                let items = try await spotifyClient.queue(accessToken: token)
                guard Task.isCancelled == false else { return }
                let visibleItems = Array(items.prefix(50))
                if queueItems.isEmpty {
                    queueItems = visibleItems
                    queueStatusText = visibleItems.isEmpty ? "다음 곡 없음" : nil
                }
                lastQueuePoll = Date()
                prefetchLyrics(for: Array(visibleItems.prefix(3)))
            } catch SpotifyAPIError.rateLimited(let retryAfter) {
                guard Task.isCancelled == false else { return }
                applySpotifyRateLimit(retryAfter, reason: "queue 프리패치")
            } catch {
                return
            }
        }
    }

    private func prefetchLyrics(for items: [QueueItemInfo]) {
        guard demoMode == false else { return }
        let tracks = items
            .map { $0.approximateTrackInfo() }
            .filter { track in
                let key = LyricsCacheKey(track: track)
                return lyricsCache[key] == nil && lyricsDiskCache.lyrics(for: key) == nil
            }

        guard tracks.isEmpty == false else { return }

        lyricsPrefetchTask?.cancel()
        lyricsPrefetchTask = Task { [weak self] in
            guard let self else { return }
            for track in tracks {
                guard Task.isCancelled == false else { return }
                _ = try? await cachedLyrics(for: track)
            }
        }
    }

    private func applyDemoQueueSelection(_ item: QueueItemInfo, statusPrefix: String) {
        let track = item.approximateTrackInfo()
        currentTrack = track
        currentLyrics = .plain([item.title])
        displayState = .playing(track)
        caption = CaptionLines(current: item.title, next: nil, isFallback: true)
        statusText = "\(statusPrefix): \(item.title)"
    }

    private func applySpotifyRateLimit(_ retryAfter: TimeInterval, reason: String) {
        let waitSeconds = max(1, retryAfter)
        let until = Date().addingTimeInterval(waitSeconds)
        if let current = spotifyRateLimitedUntil, current > until {
            return
        }

        spotifyRateLimitedUntil = until
        let rounded = Int(ceil(waitSeconds))
        let message = "Spotify 요청 제한 · \(rounded)초 후 재개"
        statusText = "\(message) (\(reason))"
    }

    private func spotifyRateLimitRemaining(now: Date = Date()) -> TimeInterval? {
        guard let spotifyRateLimitedUntil else {
            return nil
        }

        let remaining = spotifyRateLimitedUntil.timeIntervalSince(now)
        if remaining <= 0 {
            self.spotifyRateLimitedUntil = nil
            return nil
        }

        return remaining
    }

    private func cachedLyrics(for track: TrackInfo) async throws -> LyricsPayload {
        let key = LyricsCacheKey(track: track)
        if let cached = lyricsCache[key] {
            return cached
        }

        if let cached = lyricsDiskCache.lyrics(for: key) {
            lyricsCache[key] = cached
            return cached
        }

        if let request = lyricsRequests[key] {
            return try await request.value
        }

        let client = lrclibClient
        let request = Task<LyricsPayload, Error> {
            try await client.lyrics(for: track)
        }
        lyricsRequests[key] = request

        do {
            let lyrics = try await request.value
            lyricsCache[key] = lyrics
            lyricsDiskCache.store(lyrics, for: key)
            lyricsRequests[key] = nil
            return lyrics
        } catch {
            lyricsRequests[key] = nil
            throw error
        }
    }

    private func displayableLyrics(_ lyrics: LyricsPayload) -> LyricsPayload {
        return lyrics
    }

    private func statusText(for lyrics: LyricsPayload) -> String {
        switch lyrics {
        case .synced:
            return "싱크 가사 표시 중"
        case .plain:
            return "싱크 없는 원문 가사 표시 중"
        case .missing:
            return "가사를 찾지 못했어"
        }
    }

    private func updateCaption() {
        guard let track = currentTrack else {
            caption = .empty
            return
        }

        guard isPlaybackActive else {
            return
        }

        let elapsed = Date().timeIntervalSince(track.capturedAt)
        let progress = Double(track.progressMilliseconds) / 1000 + elapsed
        let updated = LyricsParser.caption(
            for: currentLyrics,
            progress: progress,
            duration: Double(track.durationMilliseconds) / 1000,
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

    private var demoQueueItems: [QueueItemInfo] {
        [
            QueueItemInfo(id: "demo-1", title: "Blinding Lights", artist: "The Weeknd", kind: "track", uri: "spotify:track:0VjIjW4GlUZAMYd2vXMi3b"),
            QueueItemInfo(id: "demo-2", title: "Instant Crush", artist: "Daft Punk, Julian Casablancas", kind: "track", uri: "spotify:track:2cGxRwrMyEAp8dEbuZaVv6"),
            QueueItemInfo(id: "demo-3", title: "Sweet Disposition", artist: "The Temper Trap", kind: "track", uri: "spotify:track:5RoIXwyTCdyUjpMMkk4uPd"),
            QueueItemInfo(id: "demo-4", title: "Electric Feel", artist: "MGMT", kind: "track", uri: "spotify:track:3FtYbEfBqAlGO46NUDQSAt"),
            QueueItemInfo(id: "demo-5", title: "1901", artist: "Phoenix", kind: "track", uri: "spotify:track:1Ug5wxoHthwxctyWTUMGta"),
            QueueItemInfo(id: "demo-6", title: "Midnight City", artist: "M83", kind: "track", uri: "spotify:track:1eyzqe2QqGZUmfcPZtrIyt"),
            QueueItemInfo(id: "demo-7", title: "Young Folks", artist: "Peter Bjorn and John", kind: "track", uri: "spotify:track:4dyx5SzxPPaD8xQIid5Wjj"),
            QueueItemInfo(id: "demo-8", title: "Lisztomania", artist: "Phoenix", kind: "track", uri: "spotify:track:7fmJGzyvNdfk2gbkQncUuS")
        ]
    }
}
