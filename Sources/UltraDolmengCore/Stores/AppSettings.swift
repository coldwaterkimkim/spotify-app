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

    @Published var mousePassThrough: Bool {
        didSet { defaults.set(mousePassThrough, forKey: Keys.mousePassThrough) }
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

    @Published var bottomOffset: Double {
        didSet { defaults.set(bottomOffset, forKey: Keys.bottomOffset) }
    }

    @Published var pauseFadeDelay: Double {
        didSet { defaults.set(pauseFadeDelay, forKey: Keys.pauseFadeDelay) }
    }

    @Published var lyricsOffset: Double {
        didSet { defaults.set(lyricsOffset, forKey: Keys.lyricsOffset) }
    }

    @Published var showPlainLyricsFallback: Bool {
        didSet { defaults.set(showPlainLyricsFallback, forKey: Keys.showPlainLyricsFallback) }
    }

    let redirectURIHint = "http://127.0.0.1:43879/callback"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        mousePassThrough = defaults.object(forKey: Keys.mousePassThrough) as? Bool ?? false
        captionOpacity = defaults.object(forKey: Keys.captionOpacity) as? Double ?? 0.74
        captionFontSize = defaults.object(forKey: Keys.captionFontSize) as? Double ?? CaptionLayout.defaultFontSize
        captionMaxWidth = defaults.object(forKey: Keys.captionMaxWidth) as? Double ?? CaptionLayout.defaultMaxWidth
        bottomOffset = defaults.object(forKey: Keys.bottomOffset) as? Double ?? 86
        pauseFadeDelay = defaults.object(forKey: Keys.pauseFadeDelay) as? Double ?? 3
        lyricsOffset = defaults.object(forKey: Keys.lyricsOffset) as? Double ?? 0
        showPlainLyricsFallback = defaults.object(forKey: Keys.showPlainLyricsFallback) as? Bool ?? true
    }
}

private enum Keys {
    static let spotifyClientID = "spotifyClientID"
    static let alwaysOnTop = "alwaysOnTop"
    static let mousePassThrough = "mousePassThrough"
    static let captionOpacity = "captionOpacity"
    static let captionFontSize = "captionFontSize"
    static let captionMaxWidth = "captionMaxWidth"
    static let bottomOffset = "bottomOffset"
    static let pauseFadeDelay = "pauseFadeDelay"
    static let lyricsOffset = "lyricsOffset"
    static let showPlainLyricsFallback = "showPlainLyricsFallback"
}

enum CaptionLayout {
    static let defaultFontSize: Double = 22
    static let minFontSize: Double = 1
    static let maxFontSize: Double = 22
    static let defaultMaxWidth: Double = 560
    static let minMaxWidth: Double = 360
    static let maxMaxWidth: Double = 860
    static let windowHorizontalInset: Double = 56
    static let windowAspectRatio: Double = 5.65

    static func visualScale(for fontSize: Double) -> Double {
        let clampedFontSize = min(max(fontSize, minFontSize), maxFontSize)
        return clampedFontSize / defaultFontSize
    }

    static func fontSize(for storedFontSize: Double) -> Double {
        min(max(storedFontSize, minFontSize), maxFontSize)
    }
}
