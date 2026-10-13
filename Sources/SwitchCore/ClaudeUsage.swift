import Foundation

// Claude usage from files the Claude apps already write. Nothing here uses credentials or calls an API:
// - The desktop app records plan usage (5-hour and weekly percentages per organization) in its data folder,
//   but no reset times, so the 5-hour reset is estimated from when the window started filling and the weekly
//   reset comes from a day and time the user copies once from Claude's settings.
// - Claude Code writes an exact `resetsAt` into its transcript when a request is refused for a usage limit.

/// One record from the desktop app's `plan-usage-history.json`.
public struct ClaudeUsageSample: Equatable {
    public let org: String
    public let time: Date
    /// Used percentages.
    public let fiveHour: Double
    public let weekly: Double
    public init(org: String, time: Date, fiveHour: Double, weekly: Double) {
        self.org = org; self.time = time; self.fiveHour = fiveHour; self.weekly = weekly
    }
}

/// The weekly reset as Claude's settings show it, e.g. Friday 11:00 (Korea time, like every date in this app).
public struct WeeklyReset: Codable, Equatable {
    /// Calendar weekday: 1 = Sunday … 7 = Saturday.
    public let weekday: Int
    public let hour: Int
    public let minute: Int
    public init?(weekday: Int, hour: Int, minute: Int) {
        guard (1...7).contains(weekday), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.weekday = weekday; self.hour = hour; self.minute = minute
    }
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }
    public func next(after date: Date) -> Date {
        Self.calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                               matchingPolicy: .nextTime) ?? date.addingTimeInterval(7 * 86400)
    }
    public func previous(atOrBefore date: Date) -> Date { next(after: date).addingTimeInterval(-7 * 86400) }
}

/// A request Claude refused for a usage limit, with the exact time the limit lifts.
public struct ClaudeQuotaBlock: Equatable {
    /// `five_hour`, `seven_day`, or a model-specific weekly limit.
    public let window: String
    public let resetsAt: Date
    public let observed: Date
    public init(window: String, resetsAt: Date, observed: Date) {
        self.window = window; self.resetsAt = resetsAt; self.observed = observed
    }
    public var isWeekly: Bool { window.hasPrefix("seven_day") }
}

public struct ClaudeUsageEstimate: Equatable {
    public let org: String
    /// When the desktop app last recorded usage for this account.
    public let observed: Date
    public let fiveHourUsed: Double
    /// Estimated: when the current 5-hour window started filling, plus five hours. Nil when the window is empty.
    public let fiveHourReset: Date?
    public let weeklyUsed: Double
    /// From the user's weekly reset setting; nil until it is set.
    public let weeklyReset: Date?

    public var fiveHourLeft: Double { max(0, 100 - fiveHourUsed) }
    public var weeklyLeft: Double { max(0, 100 - weeklyUsed) }
}

public enum ClaudeUsage {
    public static let historyFile = "plan-usage-history.json"
    public static let fiveHours: TimeInterval = 5 * 3600
    /// Samples further apart than this are not treated as one continuous reading.
    static let sampleGap: TimeInterval = 30 * 60

    /// Usage records in a Claude desktop data folder. Empty when the file is missing or unreadable.
    public static func samples(inFolder folder: URL) -> [ClaudeUsageSample] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(historyFile)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["samples"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let org = item["org"] as? String, let ms = (item["t"] as? NSNumber)?.doubleValue,
                  let usage = item["u"] as? [String: Any],
                  let five = (usage["fh"] as? NSNumber)?.doubleValue, let week = (usage["sd"] as? NSNumber)?.doubleValue
            else { return nil }
            return ClaudeUsageSample(org: org, time: Date(timeIntervalSince1970: ms / 1000), fiveHour: five, weekly: week)
        }
    }

    /// The organization with the most recent record.
    public static func latestOrg(_ samples: [ClaudeUsageSample]) -> String? { samples.max { $0.time < $1.time }?.org }

    /// The current picture for one organization (the most recently recorded one by default).
    public static func estimate(_ samples: [ClaudeUsageSample], org: String? = nil, weekly: WeeklyReset?, now: Date) -> ClaudeUsageEstimate? {
        guard let org = org ?? latestOrg(samples) else { return nil }
        let series = samples.filter { $0.org == org && $0.time <= now }.sorted { $0.time < $1.time }
        guard let last = series.last else { return nil }

        // A 5-hour window starts with the first use after an empty or expired one. Usage only grows inside a
        // window, so a drop also means a new window began.
        var start: Date?
        var previous: ClaudeUsageSample?
        for sample in series {
            defer { previous = sample }
            guard sample.fiveHour > 0 else { start = nil; continue }
            if let begun = start, sample.time.timeIntervalSince(begun) < fiveHours,
               let before = previous, sample.fiveHour >= before.fiveHour { continue }
            // The window began between the previous record and this one; take the earlier time when they are close.
            if let before = previous, before.fiveHour <= 0, sample.time.timeIntervalSince(before.time) <= sampleGap {
                start = before.time.addingTimeInterval(sample.time.timeIntervalSince(before.time) / 2)
            } else { start = sample.time }
        }
        var fiveUsed = last.fiveHour
        var fiveReset = start.map { $0.addingTimeInterval(fiveHours) }
        if fiveUsed <= 0 || fiveReset.map({ $0 <= now }) == true || now.timeIntervalSince(last.time) >= fiveHours {
            fiveUsed = 0; fiveReset = nil
        }
        var weekUsed = last.weekly
        if let weekly, weekly.previous(atOrBefore: now) > last.time { weekUsed = 0 }
        return ClaudeUsageEstimate(org: org, observed: last.time, fiveHourUsed: fiveUsed, fiveHourReset: fiveReset,
                                   weeklyUsed: weekUsed, weeklyReset: weekly?.next(after: now))
    }
}

/// Finds the latest usage-limit refusal Claude Code recorded in a config folder's transcripts
/// (`<config>/projects/**/*.jsonl`). Reads only the end of recently changed files and remembers results.
public final class ClaudeQuotaScanner {
    /// Bytes read from the end of each transcript. A refusal that still applies is among a session's last lines.
    static let tailBytes = 512 * 1024
    private var cache: [String: (modified: Date, size: Int, blocks: [Found])] = [:]
    struct Found { let block: ClaudeQuotaBlock; let entrypoint: String? }

    public init() {}

    /// - Parameters:
    ///   - entrypoint: which writers count, e.g. only the desktop Code tab (`claude-desktop`) or only the terminal.
    ///   - since: ignore refusals recorded before this (e.g. before the desktop account last changed).
    public func activeBlock(configFolder: URL, now: Date, since: Date? = nil,
                            entrypoint: (String?) -> Bool = { _ in true }) -> ClaudeQuotaBlock? {
        let projects = configFolder.appendingPathComponent("projects")
        let oldest = max(now.addingTimeInterval(-7 * 86400), since ?? .distantPast)
        guard let walker = FileManager.default.enumerator(at: projects, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]) else { return nil }
        var best: ClaudeQuotaBlock?
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, let modified = values.contentModificationDate, modified >= oldest else { continue }
            let size = values.fileSize ?? 0
            let found: [Found]
            if let hit = cache[url.path], hit.modified == modified, hit.size == size { found = hit.blocks }
            else {
                found = Self.refusals(in: url, size: size)
                cache[url.path] = (modified, size, found)
            }
            for item in found where item.block.resetsAt > now && item.block.observed >= oldest && entrypoint(item.entrypoint) {
                if best == nil || item.block.observed > best!.observed { best = item.block }
            }
        }
        return best
    }

    static func refusals(in url: URL, size: Int) -> [Found] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let offset = max(0, size - tailBytes)
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd() else { return [] }
        return refusals(in: data)
    }

    static func refusals(in data: Data) -> [Found] {
        let marker = Data(#""quotaLimits""#.utf8)
        guard data.range(of: marker) != nil else { return [] }
        var result: [Found] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let quota = object["quotaLimits"] as? [String: Any], quota["status"] as? String == "rejected",
                  let resets = (quota["resetsAt"] as? NSNumber)?.doubleValue, resets > 0,
                  let stamp = object["timestamp"] as? String, let observed = parseTimestamp(stamp) else { continue }
            let window = quota["rateLimitType"] as? String ?? "five_hour"
            result.append(Found(block: ClaudeQuotaBlock(window: window, resetsAt: Date(timeIntervalSince1970: resets), observed: observed),
                                entrypoint: object["entrypoint"] as? String))
        }
        return result
    }

    static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Per-account settings for Claude usage, kept in this app's own folder.
public final class ClaudeUsageSettings {
    public let file: URL
    public init(file: URL) { self.file = file }

    private struct Stored: Codable { var weeklyResets: [String: WeeklyReset] = [:] }
    private func load() -> Stored {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }
    public func weeklyReset(account: String) -> WeeklyReset? { load().weeklyResets[account] }
    public func setWeeklyReset(_ value: WeeklyReset?, account: String) throws {
        var stored = load()
        stored.weeklyResets[account] = value
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stored).write(to: file, options: .atomic)
    }
}
