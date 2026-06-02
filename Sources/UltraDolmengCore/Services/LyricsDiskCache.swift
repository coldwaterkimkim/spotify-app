import CryptoKit
import Foundation

final class LyricsDiskCache {
    private let directory: URL
    private let positiveTTL: TimeInterval
    private let negativeTTL: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        directory: URL? = nil,
        positiveTTL: TimeInterval = 60 * 60 * 24 * 180,
        negativeTTL: TimeInterval = 60 * 30
    ) {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? cacheDirectory
            .appendingPathComponent("com.ultradolmeng.spotifylyrics", isDirectory: true)
            .appendingPathComponent("Lyrics", isDirectory: true)
        self.positiveTTL = positiveTTL
        self.negativeTTL = negativeTTL

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func lyrics(for key: LyricsCacheKey) -> LyricsPayload? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(CachedLyricsRecord.self, from: data) else {
            return nil
        }

        let age = Date().timeIntervalSince(record.storedAt)
        if record.kind == .missing {
            guard age <= negativeTTL else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        } else if age > positiveTTL {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return record.payload
    }

    func store(_ payload: LyricsPayload, for key: LyricsCacheKey) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let record = CachedLyricsRecord(payload: payload, storedAt: Date())
            let data = try encoder.encode(record)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Disk cache is only an optimization; playback should never fail because of it.
        }
    }

    func remove(_ key: LyricsCacheKey) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func fileURL(for key: LyricsCacheKey) -> URL {
        directory.appendingPathComponent(Self.fileName(for: key), isDirectory: false)
    }

    private static func fileName(for key: LyricsCacheKey) -> String {
        let digest = SHA256.hash(data: Data(key.storageIdentifier.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).json"
    }
}

private struct CachedLyricsRecord: Codable {
    enum Kind: String, Codable {
        case synced
        case plain
        case missing
    }

    let version: Int
    let storedAt: Date
    let kind: Kind
    let syncedLines: [CachedLyricsLine]?
    let plainLines: [String]?

    init(payload: LyricsPayload, storedAt: Date) {
        version = 1
        self.storedAt = storedAt

        switch payload {
        case .synced(let lines):
            kind = .synced
            syncedLines = lines.map { CachedLyricsLine(time: $0.time, text: $0.text) }
            plainLines = nil
        case .plain(let lines):
            kind = .plain
            syncedLines = nil
            plainLines = lines
        case .missing:
            kind = .missing
            syncedLines = nil
            plainLines = nil
        }
    }

    var payload: LyricsPayload {
        switch kind {
        case .synced:
            return .synced((syncedLines ?? []).map { LyricsLine(time: $0.time, text: $0.text) })
        case .plain:
            return .plain(plainLines ?? [])
        case .missing:
            return .missing
        }
    }
}

private struct CachedLyricsLine: Codable {
    let time: TimeInterval
    let text: String
}
