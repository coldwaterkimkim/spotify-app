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
    @Published private(set) var likedSongsWarmupStatusText = "좋아요 곡 캐시 대기 중"
    @Published private(set) var isLikedSongsWarmupActive = false
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
    private var likedSongsWarmupTask: Task<Void, Never>?
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

    func start() {
        isConnected = authService.storedToken() != nil
        displayState = isConnected ? .idle : .disconnected
        startTimers()
        startLikedSongsWarmupIfNeeded()
    }

    func stop() {
        pollingTimer?.invalidate()
        captionTimer?.invalidate()
        queueTask?.cancel()
        queuePrefetchTask?.cancel()
        lyricsPrefetchTask?.cancel()
        likedSongsWarmupTask?.cancel()
        lyricsTask?.cancel()
        lyricsRetryTask?.cancel()
        lyricsRequests.values.forEach { $0.cancel() }
        pollingTimer = nil
        captionTimer = nil
        queueTask = nil
        queuePrefetchTask = nil
        lyricsPrefetchTask = nil
        likedSongsWarmupTask = nil
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
                startLikedSongsWarmupIfNeeded(force: true)
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
            stopLikedSongsWarmup()
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

    func startLikedSongsWarmupIfNeeded(force: Bool = false) {
        guard settings.likedSongsWarmupEnabled else {
            stopLikedSongsWarmup()
            likedSongsWarmupStatusText = "좋아요 곡 캐시 꺼짐"
            return
        }

        guard isConnected else {
            likedSongsWarmupStatusText = "Spotify 연결 후 좋아요 곡 캐시 가능"
            return
        }

        if force {
            likedSongsWarmupTask?.cancel()
            likedSongsWarmupTask = nil
        } else if likedSongsWarmupTask != nil {
            return
        }

        likedSongsWarmupTask = Task { [weak self] in
            await self?.runLikedSongsWarmup(force: force)
        }
    }

    func restartLikedSongsWarmup() {
        settings.likedSongsWarmupResumeOffset = 0
        settings.likedSongsWarmupLastRun = nil
        startLikedSongsWarmupIfNeeded(force: true)
    }

    func stopLikedSongsWarmup() {
        likedSongsWarmupTask?.cancel()
        likedSongsWarmupTask = nil
        isLikedSongsWarmupActive = false
        likedSongsWarmupStatusText = "좋아요 곡 캐시 꺼짐"
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
            statusText = "미리보기 queue 선택: \(item.title)"
            caption = CaptionLines(current: item.title, next: nil, isFallback: true)
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
            caption = CaptionLines(current: item.title, next: nil, isFallback: true)
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

    private func runLikedSongsWarmup(force: Bool) async {
        var shouldForceFullSweep = force
        isLikedSongsWarmupActive = true

        do {
            while Task.isCancelled == false, settings.likedSongsWarmupEnabled, isConnected {
                let total = try await warmRecentLikedSongs()
                let shouldSweepLibrary = shouldForceFullSweep
                    || settings.likedSongsWarmupLastRun == nil
                    || settings.likedSongsWarmupResumeOffset > 0

                if shouldSweepLibrary, total > 0 {
                    try await warmLikedSongsLibrary(total: total, force: shouldForceFullSweep)
                } else if total == 0 {
                    likedSongsWarmupStatusText = "좋아요 표시한 곡이 아직 없어"
                }

                settings.likedSongsWarmupLastRun = Date()
                shouldForceFullSweep = false

                if Task.isCancelled == false, settings.likedSongsWarmupEnabled {
                    likedSongsWarmupStatusText = "좋아요 곡 캐시 대기 중 · \(likedSongsWarmupStats)"
                    try await Task.sleep(nanoseconds: LikedSongsWarmup.recentSweepIntervalNanoseconds)
                }
            }
        } catch is CancellationError {
            // Normal when the user disconnects, quits, or turns this feature off.
        } catch SpotifyAPIError.requestFailed(let status, _) where status == 403 {
            likedSongsWarmupStatusText = "좋아요 곡 권한 필요 · Spotify 다시 연결"
        } catch LikedSongsWarmupError.disconnected {
            likedSongsWarmupStatusText = "Spotify 연결 후 좋아요 곡 캐시 가능"
        } catch {
            likedSongsWarmupStatusText = "좋아요 곡 캐시 일시 중단 · \(error.localizedDescription)"
        }

        isLikedSongsWarmupActive = false
    }

    @discardableResult
    private func warmRecentLikedSongs() async throws -> Int {
        let recentPages = 2
        var total = 0

        for pageIndex in 0..<recentPages {
            try Task.checkCancellation()
            let offset = pageIndex * LikedSongsWarmup.pageSize
            let page = try await likedSongsPage(offset: offset)
            total = page.total
            settings.likedSongsWarmupTotal = page.total

            guard page.items.isEmpty == false else {
                break
            }

            try await warmLikedSongTracks(
                page.trackInfos(),
                phase: "최근 좋아요 확인",
                visibleOffset: page.offset,
                total: page.total
            )

            if page.offset + page.items.count >= page.total {
                break
            }

            try Task.checkCancellation()
        }

        return total
    }

    private func warmLikedSongsLibrary(total: Int, force: Bool) async throws {
        var offset = force ? 0 : settings.likedSongsWarmupResumeOffset
        let recentScanUpperBound = min(LikedSongsWarmup.pageSize * 2, total)

        if force == false, offset < recentScanUpperBound {
            offset = recentScanUpperBound
        }

        if offset >= total {
            offset = 0
        }

        while Task.isCancelled == false, offset < total {
            let page = try await likedSongsPage(offset: offset)
            settings.likedSongsWarmupTotal = page.total

            guard page.items.isEmpty == false else {
                settings.likedSongsWarmupResumeOffset = 0
                break
            }

            likedSongsWarmupStatusText = "좋아요 곡 전체 캐시 중 \(min(page.offset + page.items.count, page.total))/\(page.total)"
            try await warmLikedSongTracks(
                page.trackInfos(),
                phase: "좋아요 곡 전체 캐시",
                visibleOffset: page.offset,
                total: page.total
            )

            let nextOffset = page.offset + page.items.count
            if nextOffset >= page.total {
                settings.likedSongsWarmupResumeOffset = 0
                likedSongsWarmupStatusText = "좋아요 곡 전체 훑기 완료 · \(likedSongsWarmupStats)"
                break
            }

            settings.likedSongsWarmupResumeOffset = nextOffset
            offset = nextOffset
            try Task.checkCancellation()
        }
    }

    private func warmLikedSongTracks(
        _ tracks: [TrackInfo],
        phase: String,
        visibleOffset: Int,
        total: Int
    ) async throws {
        let workItems = tracks.enumerated().map { index, track in
            LikedSongsWarmupWorkItem(
                track: track,
                displayIndex: min(visibleOffset + index + 1, total)
            )
        }

        for batchStart in stride(
            from: 0,
            to: workItems.count,
            by: LikedSongsWarmup.maxConcurrentLyricsRequests
        ) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + LikedSongsWarmup.maxConcurrentLyricsRequests, workItems.count)
            let batch = Array(workItems[batchStart..<batchEnd])
            likedSongsWarmupStatusText = "\(phase) \(batch.first?.displayIndex ?? visibleOffset + 1)-\(batch.last?.displayIndex ?? visibleOffset + 1)/\(total) · 동시 \(LikedSongsWarmup.maxConcurrentLyricsRequests)곡"

            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try await self.warmLikedSongTrack(
                            item.track,
                            phase: phase,
                            displayIndex: item.displayIndex,
                            total: total
                        )
                    }
                }

                try await group.waitForAll()
            }
        }
    }

    private func warmLikedSongTrack(
        _ track: TrackInfo,
        phase: String,
        displayIndex: Int,
        total: Int
    ) async throws {
        try Task.checkCancellation()
        settings.likedSongsWarmupScannedCount += 1

        let key = LyricsCacheKey(track: track)
        if lyricsCache[key] != nil || lyricsDiskCache.lyrics(for: key) != nil {
            likedSongsWarmupStatusText = "\(phase) \(displayIndex)/\(total) · 이미 캐시됨"
            return
        }

        likedSongsWarmupStatusText = "\(phase) \(displayIndex)/\(total) · \(track.title)"
        do {
            _ = try await cachedLyrics(for: track)
            settings.likedSongsWarmupCachedCount += 1
        } catch {
            guard Task.isCancelled == false else { throw CancellationError() }
        }
    }

    private func likedSongsPage(offset: Int) async throws -> SpotifySavedTracksResponse {
        while Task.isCancelled == false {
            try await waitForSpotifyRateLimitIfNeeded(reason: "좋아요 곡 캐시")

            guard let token = try await authService.validAccessToken(clientID: settings.spotifyClientID) else {
                throw LikedSongsWarmupError.disconnected
            }

            do {
                return try await spotifyClient.savedTracks(
                    accessToken: token,
                    limit: LikedSongsWarmup.pageSize,
                    offset: offset
                )
            } catch SpotifyAPIError.rateLimited(let retryAfter) {
                applySpotifyRateLimit(retryAfter, reason: "좋아요 곡 캐시")
            }
        }

        throw CancellationError()
    }

    private var likedSongsWarmupStats: String {
        let total = settings.likedSongsWarmupTotal
        let scanned = settings.likedSongsWarmupScannedCount
        let cached = settings.likedSongsWarmupCachedCount

        if total > 0 {
            return "전체 \(total), 누적 확인 \(scanned), 새 캐시 \(cached)"
        }

        return "누적 확인 \(scanned), 새 캐시 \(cached)"
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
        likedSongsWarmupStatusText = message
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

    private func waitForSpotifyRateLimitIfNeeded(reason: String) async throws {
        guard let targetUntil = spotifyRateLimitedUntil,
              let remaining = spotifyRateLimitRemaining() else {
            return
        }

        let rounded = Int(ceil(remaining))
        likedSongsWarmupStatusText = "Spotify 요청 제한 · \(rounded)초 쉬는 중"
        statusText = "Spotify 요청 제한 · \(rounded)초 쉬는 중 (\(reason))"
        try await Task.sleep(nanoseconds: UInt64(max(0.1, remaining) * 1_000_000_000))
        if spotifyRateLimitedUntil == targetUntil {
            spotifyRateLimitedUntil = nil
        }
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

        guard track.isPlaying || demoMode else {
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

private enum LikedSongsWarmup {
    static let pageSize = 50
    static let maxConcurrentLyricsRequests = 32
    static let recentSweepIntervalNanoseconds: UInt64 = 24 * 60 * 60 * 1_000_000_000
}

private struct LikedSongsWarmupWorkItem {
    let track: TrackInfo
    let displayIndex: Int
}

private enum LikedSongsWarmupError: LocalizedError {
    case disconnected

    var errorDescription: String? {
        switch self {
        case .disconnected:
            return "Spotify 연결이 필요해."
        }
    }
}
