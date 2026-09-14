import Foundation

/// A quota percentage is not a token balance. Missing values remain unknown.
public struct UsageWindow: Codable, Equatable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public init(usedPercent: Double?, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
    public var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
    public var title: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return L10n.text("사용 한도") }
        if minutes == 10080 { return L10n.text("주간") }
        if minutes % 1440 == 0 { return L10n.format("%@일", String(minutes / 1440)) }
        if minutes % 60 == 0 { return L10n.format("%@시간", String(minutes / 60)) }
        return L10n.format("%@분", String(minutes))
    }
    public func resetPassed(at date: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= date.timeIntervalSince1970
    }
}

public struct UsageLimit: Codable, Equatable {
    public let planType: String?
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public init(planType: String?, primary: UsageWindow?, secondary: UsageWindow?) {
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }
}

public enum UsageSource: Equatable {
    /// Synthetic demo values.
    case demo
    /// A reading returned by a live account query (transport still disconnected).
    case live
    /// The last reading Codex itself recorded in a local session log.
    case sessionLog
}

public struct UsageSnapshot {
    public let profileID: String
    public let plan: String?
    public let limit: UsageLimit?
    public let observedAt: Date
    public let source: UsageSource
    public var isDemo: Bool { source == .demo }
    public init(profileID: String, plan: String?, limit: UsageLimit?, observedAt: Date, source: UsageSource) {
        self.profileID = profileID
        self.plan = plan
        self.limit = limit
        self.observedAt = observedAt
        self.source = source
    }

    public static func parse(_ data: Data, profileID: String, plan: String?, observedAt: Date, isDemo: Bool = false) throws -> UsageSnapshot {
        try parse(data, profileID: profileID, plan: plan, observedAt: observedAt, source: isDemo ? .demo : .live)
    }
    public static func parse(_ data: Data, profileID: String, plan: String?, observedAt: Date, source: UsageSource) throws -> UsageSnapshot {
        struct Payload: Decodable {
            let rateLimits: UsageLimit?
            let rateLimitsByLimitId: [String: UsageLimit]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        // Never substitute a different metered bucket for Codex.
        let limit = payload.rateLimitsByLimitId.map { $0["codex"] } ?? payload.rateLimits
        return UsageSnapshot(profileID: profileID, plan: plan ?? limit?.planType, limit: limit, observedAt: observedAt, source: source)
    }
    public var planLabel: String {
        guard let plan, !plan.isEmpty else { return L10n.text("요금제 미확인") }
        let lowered = plan.lowercased()
        switch lowered {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "free": return "Free"
        case "business", "team": return "Business"
        case "enterprise": return "Enterprise"
        default: break
        }
        if lowered.contains("enterprise") { return "Enterprise" }
        if lowered.contains("business") || lowered.contains("team") { return "Business" }
        return plan.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
    /// Session-log readings only change when Codex runs, so they show their recorded time instead of a refresh warning.
    public func isStale(at date: Date) -> Bool { source != .sessionLog && date.timeIntervalSince(observedAt) > 300 }
    public var windows: [UsageWindow] { [limit?.primary, limit?.secondary].compactMap { $0 } }
    public var preferredWindow: UsageWindow? { windows.first { $0.windowDurationMins == 10080 } ?? windows.first }

    public static func demo(profileID: String, index: Int, now: Date = Date()) throws -> UsageSnapshot {
        let used = index == 0 ? 59 : 24
        let data = try JSONSerialization.data(withJSONObject: ["rateLimitsByLimitId": ["codex": [
            "primary": ["usedPercent": used, "windowDurationMins": 10080, "resetsAt": now.addingTimeInterval(259200).timeIntervalSince1970]
        ]]])
        return try parse(data, profileID: profileID, plan: index == 0 ? "plus" : "pro", observedAt: now, isDemo: true)
    }
}
