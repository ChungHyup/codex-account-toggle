import Foundation

/// A quota percentage is not a token balance. Missing values remain unknown.
public struct UsageWindow: Decodable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
    public var title: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "사용 한도" }
        if minutes == 10080 { return "주간" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)일" }
        if minutes % 60 == 0 { return "\(minutes / 60)시간" }
        return "\(minutes)분"
    }
    public func resetPassed(at date: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= date.timeIntervalSince1970
    }
}

public struct UsageLimit: Decodable {
    public let planType: String?
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
}

public struct UsageSnapshot {
    public let profileID: String
    public let plan: String?
    public let limit: UsageLimit?
    public let observedAt: Date
    public let isDemo: Bool

    public static func parse(_ data: Data, profileID: String, plan: String?, observedAt: Date, isDemo: Bool = false) throws -> UsageSnapshot {
        struct Payload: Decodable {
            let rateLimits: UsageLimit?
            let rateLimitsByLimitId: [String: UsageLimit]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        // Never substitute a different metered bucket for Codex.
        let limit = payload.rateLimitsByLimitId.map { $0["codex"] } ?? payload.rateLimits
        return UsageSnapshot(profileID: profileID, plan: plan ?? limit?.planType, limit: limit, observedAt: observedAt, isDemo: isDemo)
    }
    public var planLabel: String {
        guard let plan, !plan.isEmpty else { return "요금제 미확인" }
        switch plan.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "free": return "Free"
        case "business", "team": return "Business"
        case "enterprise": return "Enterprise"
        default: return plan
        }
    }
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(observedAt) > 300 }

    public static func demo(profileID: String, index: Int, now: Date = Date()) throws -> UsageSnapshot {
        let used = index == 0 ? [28, 59] : [8, 24]
        let data = try JSONSerialization.data(withJSONObject: ["rateLimitsByLimitId": ["codex": [
            "primary": ["usedPercent": used[0], "windowDurationMins": 300, "resetsAt": now.addingTimeInterval(8400).timeIntervalSince1970],
            "secondary": ["usedPercent": used[1], "windowDurationMins": 10080, "resetsAt": now.addingTimeInterval(259200).timeIntervalSince1970]
        ]]])
        return try parse(data, profileID: profileID, plan: index == 0 ? "plus" : "pro", observedAt: now, isDemo: true)
    }
}
