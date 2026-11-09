import Foundation

public struct CodexQuotaWindow {
    public var remaining: Double?
    public var resetsAt: Date?
    public var minutes: Double?
    public init(remaining: Double? = nil, resetsAt: Date? = nil, minutes: Double? = nil) {
        self.remaining = remaining; self.resetsAt = resetsAt; self.minutes = minutes
    }
    public static func parse(_ result: [String: Any]) -> [CodexQuotaWindow] {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let bucket = buckets?["codex"] ?? (result["rateLimits"] as? [String: Any])
        guard let bucket else { return [] }
        return ["primary", "secondary"].compactMap { key in
            guard let window = bucket[key] as? [String: Any] else { return nil }
            let used = window["usedPercent"] as? Double
            return CodexQuotaWindow(remaining: used.map { min(100, max(0, 100 - $0)) },
                resetsAt: (window["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
                minutes: window["windowDurationMins"] as? Double)
        }
    }
}

public enum CodexUsageFormat {
    public static func remaining(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: value.rounded() == value ? "%.0f%%" : "%.1f%%", value)
    }
    public static func millions(_ tokens: Int64?) -> String {
        guard let tokens else { return "— MToken" }
        return String(format: "%.3f MToken", Double(tokens) / 1_000_000)
    }
    public static func countdown(_ reset: Date?, now: Date = Date()) -> String {
        guard let reset else { return "—" }
        let seconds = max(0, Int(ceil(reset.timeIntervalSince(now))))
        guard seconds > 0 else { return "等待同步" }
        let clock = String(format: "%02d:%02d:%02d", seconds % 86400 / 3600, seconds % 3600 / 60, seconds % 60)
        return seconds >= 86400 ? "\(seconds / 86400)天 \(clock)" : clock
    }
    public static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

public struct CodexTokenCursor {
    public var offset: UInt64 = 0
    public var total: Int64?
    public init() {}
}

public final class CodexTokenCounter {
    public private(set) var daily: [String: Int64] = [:]
    private let fractional = ISO8601DateFormatter()
    private let plain = ISO8601DateFormatter()
    public init() { fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }
    public func ingest(_ event: [String: Any], cursor: inout CodexTokenCursor) {
        guard event["type"] as? String == "event_msg", let payload = event["payload"] as? [String: Any],
              payload["type"] as? String == "token_count", let stamp = event["timestamp"] as? String,
              let date = fractional.date(from: stamp) ?? plain.date(from: stamp),
              let info = payload["info"] as? [String: Any],
              let usage = info["total_token_usage"] as? [String: Any],
              let total = (usage["total_tokens"] as? NSNumber)?.int64Value, total >= 0 else { return }
        let last = ((info["last_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.int64Value
        let delta = cursor.total.map { max(0, total - $0) } ?? max(0, last ?? 0)
        cursor.total = max(cursor.total ?? 0, total)
        if delta > 0 { daily[CodexUsageFormat.day(date), default: 0] += delta }
    }
}

public final class CodexLocalUsageScanner {
    private let home: URL
    private var cursors: [String: CodexTokenCursor] = [:]
    private let counter = CodexTokenCounter()
    public init(home: URL) { self.home = home }
    public func scan(now: Date = Date()) -> Int64? {
        var paths: [String: URL] = [:]
        var foundFolder = false
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = calendar.startOfDay(for: now)
        for folder in ["sessions", "archived_sessions"] {
            let directory = home.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            foundFolder = true
            for case let file as URL in walker where file.pathExtension == "jsonl" {
                if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified < midnight { continue }
                paths[file.lastPathComponent] = file
            }
        }
        guard foundFolder else { return nil }
        let marker = Data("\"token_count\"".utf8)
        for (key, file) in paths {
            var cursor = cursors[key] ?? CodexTokenCursor()
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  UInt64(size) > cursor.offset, let input = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? input.close() }
            do {
                try input.seek(toOffset: cursor.offset)
                var buffer = Data()
                while let block = try input.read(upToCount: 262144), !block.isEmpty {
                    buffer.append(block)
                    var start = buffer.startIndex
                    while let end = buffer[start...].firstIndex(of: 10) {
                        let line = buffer[start..<end]
                        if line.range(of: marker) != nil,
                           let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                            counter.ingest(event, cursor: &cursor)
                        }
                        cursor.offset += UInt64(end - start + 1)
                        start = end + 1
                    }
                    if start > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<start) }
                }
            } catch { }
            cursors[key] = cursor
        }
        return counter.daily[CodexUsageFormat.day(now), default: 0]
    }
}
