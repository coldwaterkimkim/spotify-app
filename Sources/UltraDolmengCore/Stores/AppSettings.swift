import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var spotifyClientID: String {
        didSet { defaults.set(spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.spotifyClientID) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    @Published var captionOpacity: Double {
        didSet { defaults.set(captionOpacity, forKey: Keys.captionOpacity) }
    }

    @Published var captionFontSize: Double {
        didSet { defaults.set(captionFontSize, forKey: Keys.captionFontSize) }
    }

    @Published var captionMaxWidth: Double {
        didSet { defaults.set(captionMaxWidth, forKey: Keys.captionMaxWidth) }
    }

    @Published var pauseFadeDelay: Double {
        didSet { defaults.set(pauseFadeDelay, forKey: Keys.pauseFadeDelay) }
    }

    @Published var lyricsOffset: Double {
        didSet { defaults.set(lyricsOffset, forKey: Keys.lyricsOffset) }
    }

    let redirectURIHint = "http://127.0.0.1:43879/callback"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        captionOpacity = defaults.object(forKey: Keys.captionOpacity) as? Double ?? 0.74
        captionFontSize = defaults.object(forKey: Keys.captionFontSize) as? Double ?? CaptionLayout.defaultFontSize
        captionMaxWidth = defaults.object(forKey: Keys.captionMaxWidth) as? Double ?? CaptionLayout.defaultMaxWidth
        pauseFadeDelay = defaults.object(forKey: Keys.pauseFadeDelay) as? Double ?? 3
        lyricsOffset = defaults.object(forKey: Keys.lyricsOffset) as? Double ?? 0
    }
}

private enum Keys {
    static let spotifyClientID = "spotifyClientID"
    static let alwaysOnTop = "alwaysOnTop"
    static let captionOpacity = "captionOpacity"
    static let captionFontSize = "captionFontSize"
    static let captionMaxWidth = "captionMaxWidth"
    static let pauseFadeDelay = "pauseFadeDelay"
    static let lyricsOffset = "lyricsOffset"
}

enum CaptionLayout {
    static let defaultFontSize: Double = 22
    static let minFontSize: Double = 1
    static let maxFontSize: Double = 22
    static let defaultMaxWidth: Double = 560
    static let minMaxWidth: Double = 360
    static let maxMaxWidth: Double = 860
    static let defaultBottomOffset: Double = 86
    static let queuePanelHeight: Double = 218
    static let queuePanelSpacing: Double = 8

    static func visualScale(for fontSize: Double) -> Double {
        let clampedFontSize = min(max(fontSize, minFontSize), maxFontSize)
        return clampedFontSize / defaultFontSize
    }

    static func fontSize(for storedFontSize: Double) -> Double {
        min(max(storedFontSize, minFontSize), maxFontSize)
    }

    static func captionPanelHeight(for storedFontSize: Double) -> Double {
        ceil(fontSize(for: storedFontSize) * 1.35 + 20)
    }
}
