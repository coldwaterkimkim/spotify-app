import Foundation

enum LyricsParser {
    static func parseSyncedLyrics(_ source: String) -> [LyricsLine] {
        source
            .components(separatedBy: .newlines)
            .flatMap(parseLine)
            .filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted { $0.time < $1.time }
    }

    static func parsePlainLyrics(_ source: String) -> [String] {
        source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    static func caption(
        for payload: LyricsPayload,
        progress: TimeInterval,
        duration: TimeInterval?,
        offset: TimeInterval
    ) -> CaptionLines {
        switch payload {
        case .synced(let lines):
            return syncedCaption(lines: lines, progress: max(0, progress + offset))
        case .plain(let lines):
            return plainCaption(lines: lines, progress: max(0, progress + offset), duration: duration)
        case .missing:
            return .empty
        }
    }

    private static func syncedCaption(lines: [LyricsLine], progress: TimeInterval) -> CaptionLines {
        guard lines.isEmpty == false else {
            return .empty
        }

        var currentIndex = 0
        for index in lines.indices {
            if lines[index].time <= progress {
                currentIndex = index
            } else {
                break
            }
        }

        let current = lines[currentIndex].text
        return CaptionLines(current: current, next: nil, isFallback: false)
    }

    private static func plainCaption(lines: [String], progress: TimeInterval, duration: TimeInterval?) -> CaptionLines {
        guard lines.isEmpty == false else {
            return .empty
        }

        guard let duration, duration > 0 else {
            return CaptionLines(current: lines[0], next: nil, isFallback: true)
        }

        let clampedProgress = min(max(0, progress), duration)
        let ratio = clampedProgress / duration
        let index = min(lines.count - 1, max(0, Int((ratio * Double(lines.count)).rounded(.down))))
        return CaptionLines(current: lines[index], next: nil, isFallback: true)
    }

    private static func parseLine(_ line: String) -> [LyricsLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, range: range)
        guard matches.isEmpty == false else {
            return []
        }

        let textStart = matches.last!.range.upperBound
        let text = String(line[String.Index(utf16Offset: textStart, in: line)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return matches.compactMap { match in
            guard let minuteRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line),
                  let minutes = Double(line[minuteRange]),
                  let seconds = Double(line[secondRange]) else {
                return nil
            }

            var fractional = 0.0
            if match.range(at: 3).location != NSNotFound,
               let fractionRange = Range(match.range(at: 3), in: line),
               let fractionValue = Double(line[fractionRange]) {
                let digits = Double(match.range(at: 3).length)
                fractional = fractionValue / pow(10, digits)
            }

            return LyricsLine(time: minutes * 60 + seconds + fractional, text: text)
        }
    }
}
