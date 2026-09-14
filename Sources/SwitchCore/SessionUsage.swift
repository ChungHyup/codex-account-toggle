import Foundation

/// Quota readings that Codex already wrote to its own local session logs
/// (`CODEX_HOME/sessions/**/*.jsonl`, `event_msg` records of type `token_count`).
/// Reading them never launches Codex, sends no request, and never opens a credential file.
/// This mirrors the reference project's approach: show the last locally recorded reading
/// instead of asking the service, which could wake an idle account's window.
public struct SessionUsageObservation: Codable, Equatable {
    public let observedAt: Date
    public let plan: String?
    public let limit: UsageLimit
    public init(observedAt: Date, plan: String?, limit: UsageLimit) {
        self.observedAt = observedAt
        self.plan = plan
        self.limit = limit
    }
}

public enum SessionUsageReader {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses one rollout line. Returns nil unless it is a `token_count` event carrying the Codex limit.
    public static func observation(from line: Data, fallbackDate: Date) -> SessionUsageObservation? {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              record["type"] as? String == "event_msg",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = value(payload, "rate_limits", "rateLimits") as? [String: Any] else { return nil }
        // Never present another metered bucket as the Codex limit.
        if let id = value(limits, "limit_id", "limitId") as? String, id != "codex" { return nil }
        let primary = window(limits["primary"]), secondary = window(limits["secondary"])
        guard primary != nil || secondary != nil else { return nil }
        let plan = value(limits, "plan_type", "planType") as? String
        let observedAt = (record["timestamp"] as? String).flatMap(date(from:)) ?? fallbackDate
        return SessionUsageObservation(observedAt: observedAt, plan: plan, limit: UsageLimit(planType: plan, primary: primary, secondary: secondary))
    }

    /// The latest reading in each of the newest `maxFiles` rollouts. Reads the tail of each file first
    /// and falls back to a bounded full read when the tail holds no reading.
    public static func scan(sessionsRoot: URL, maxFiles: Int = 60, tailBytes: Int = 262_144, fullReadLimit: Int = 33_554_432) -> [SessionUsageObservation] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: sessionsRoot, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        var files: [(url: URL, modified: Date, size: Int)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            files.append((url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0))
        }
        files.sort { $0.modified == $1.modified ? $0.url.path < $1.url.path : $0.modified > $1.modified }
        return files.prefix(max(0, maxFiles)).compactMap { latest(in: $0.url, size: $0.size, fallbackDate: $0.modified, tailBytes: tailBytes, fullReadLimit: fullReadLimit) }
    }

    static func latest(in url: URL, size: Int, fallbackDate: Date, tailBytes: Int, fullReadLimit: Int) -> SessionUsageObservation? {
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let start = tailBytes > 0 ? max(0, size - tailBytes) : 0
        guard let tail = read(handle, from: start) else { return nil }
        if let found = last(in: tail, dropFirstLine: start > 0, fallbackDate: fallbackDate) { return found }
        guard start > 0, size <= fullReadLimit, let whole = read(handle, from: 0) else { return nil }
        return last(in: whole, dropFirstLine: false, fallbackDate: fallbackDate)
    }

    private static func read(_ handle: FileHandle, from offset: Int) -> Data? {
        do { try handle.seek(toOffset: UInt64(offset)); return try handle.readToEnd() } catch { return nil }
    }

    private static func last(in data: Data, dropFirstLine: Bool, fallbackDate: Date) -> SessionUsageObservation? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if dropFirstLine, !lines.isEmpty { lines.removeFirst() } // a tail usually starts mid-line
        let marker = Data("\"token_count\"".utf8)
        for line in lines.reversed() where line.range(of: marker) != nil {
            if let found = observation(from: line, fallbackDate: fallbackDate) { return found }
        }
        return nil
    }

    private static func window(_ raw: Any?) -> UsageWindow? {
        guard let record = raw as? [String: Any] else { return nil }
        return UsageWindow(usedPercent: number(value(record, "used_percent", "usedPercent")),
                           windowDurationMins: number(value(record, "window_minutes", "windowDurationMins", "window_duration_mins")).map { Int($0) },
                           resetsAt: number(value(record, "resets_at", "resetsAt")))
    }
    private static func value(_ record: [String: Any], _ keys: String...) -> Any? {
        for key in keys { if let found = record[key], !(found is NSNull) { return found } }
        return nil
    }
    private static func number(_ raw: Any?) -> Double? { (raw as? NSNumber)?.doubleValue }
    private static func date(from text: String) -> Date? {
        guard let parsed = fractional.date(from: text) ?? plain.date(from: text) else { return nil }
        return Date(timeIntervalSince1970: floor(parsed.timeIntervalSince1970))
    }
}

/// Session logs do not name the account. A reading is attributed to a saved profile only from
/// moments when this app confirmed which account was signed in.
public enum IdentityPointKind: String, Codable {
    /// The user saved the signed-in account; before this moment the same account is assumed.
    case saved
    /// The panel saw this account signed in; a change since the previous point happened at an unknown time.
    case observed
    /// This app replaced the sign-in at exactly this moment.
    case switched
}

public struct IdentityPoint: Codable, Equatable {
    public let at: Date
    public let id: String
    public let kind: IdentityPointKind
    public init(at: Date, id: String, kind: IdentityPointKind) { self.at = at; self.id = id; self.kind = kind }
}

public struct UsageAttributor {
    private let points: [IdentityPoint]
    public init(points: [IdentityPoint]) { self.points = points.sorted { $0.at < $1.at } }
    /// The profile signed in at `date`, or nil when the sign-in could have changed outside this app.
    public func profileID(at date: Date) -> String? {
        let before = points.last { $0.at <= date }
        let after = points.first { $0.at > date }
        if let before {
            guard let after, after.id != before.id else { return before.id }
            return after.kind == .switched ? before.id : nil
        }
        // Older than every confirmation: follow the first passive confirmation, as the reference project does.
        if let after, after.kind != .switched { return after.id }
        return nil
    }
}

public enum SessionUsage {
    /// Latest attributable reading per saved profile. Readings are cached in the profile directory
    /// so an inactive account keeps its last value after Codex rotates its logs.
    public static func collect(store: Store, profileIDs: [String], maxFiles: Int = 60) -> [String: UsageSnapshot] {
        let attributor = UsageAttributor(points: (try? store.identityPoints()) ?? [])
        var cache = (try? store.cachedUsage()) ?? [:]
        var changed = false
        for observation in SessionUsageReader.scan(sessionsRoot: store.sessions, maxFiles: maxFiles) {
            guard let id = attributor.profileID(at: observation.observedAt) else { continue }
            if let existing = cache[id], existing.observedAt >= observation.observedAt { continue }
            cache[id] = observation
            changed = true
        }
        if changed { try? store.saveUsage(cache) }
        var result: [String: UsageSnapshot] = [:]
        for id in profileIDs {
            guard let reading = cache[id] else { continue }
            result[id] = UsageSnapshot(profileID: id, plan: reading.plan ?? reading.limit.planType, limit: reading.limit, observedAt: reading.observedAt, source: .sessionLog)
        }
        return result
    }
}
