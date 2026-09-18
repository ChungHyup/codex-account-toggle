import Foundation

/// Reads a number that the service may send as a JSON string ("1319.6") or a number.
fileprivate func flexibleNumber<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let value = try? container.decode(Double.self, forKey: key), value.isFinite { return value }
    if let text = try? container.decode(String.self, forKey: key),
       let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite { return value }
    return nil
}

/// Credits that keep Codex usable after the plan limit. Workspace seats report no balance.
public struct CreditsInfo: Codable, Equatable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: Double?
    public init(hasCredits: Bool?, unlimited: Bool?, balance: Double?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
    enum CodingKeys: String, CodingKey { case hasCredits, unlimited, balance }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try? container.decode(Bool.self, forKey: .hasCredits)
        unlimited = try? container.decode(Bool.self, forKey: .unlimited)
        balance = flexibleNumber(container, .balance)
    }
}

/// Monthly credit cap an admin set for a workspace seat, in credits.
public struct SpendLimit: Codable, Equatable {
    public let limit: Double?
    public let used: Double?
    public let remainingPercent: Double?
    public let resetsAt: Double?
    public init(limit: Double?, used: Double?, remainingPercent: Double?, resetsAt: Double?) {
        self.limit = limit
        self.used = used
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
    enum CodingKeys: String, CodingKey { case limit, used, remainingPercent, resetsAt }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = flexibleNumber(container, .limit)
        used = flexibleNumber(container, .used)
        remainingPercent = flexibleNumber(container, .remainingPercent)
        resetsAt = flexibleNumber(container, .resetsAt)
    }
}

/// Credit mode: the plan's weekly allowance is used up and Codex keeps working on credits,
/// or usage is blocked. Business seats are shown by the remaining share of their monthly cap,
/// personal accounts by their credit balance.
public struct CreditStatus: Equatable {
    public enum Kind: Equatable { case spending, blocked }
    public let kind: Kind
    public let blockedByCredits: Bool
    public let capRemainingPercent: Double?
    public let capUsed: Double?
    public let capLimit: Double?
    public let capResetsAt: Double?
    public let balance: Double?

    /// Menu-bar value: "47%" for a capped seat, "2.8K" or "850" for a balance, nil when unknown.
    public var shortValue: String? {
        if let capRemainingPercent { return CreditFormat.percent(capRemainingPercent) }
        if let balance { return CreditFormat.compact(balance) }
        return nil
    }
    /// Grows while credits are consumed: cap usage, or the negated balance.
    public var consumptionMeter: Double? { capUsed ?? balance.map { -$0 } }

    public func headline(burning: Bool) -> String {
        switch kind {
        case .blocked: return L10n.text(blockedByCredits ? "크레딧 소진 · 사용이 중지됨" : "사용 한도 도달 · 사용이 중지됨")
        case .spending: return L10n.text("크레딧 사용 중") + (burning ? " · " + L10n.text("차감 중") : "")
        }
    }
    /// One short line for the panel.
    public func detail(now: Date, language: AppLanguage = L10n.language) -> String? {
        if let capRemainingPercent {
            var text = L10n.format("크레딧 한도 %@ 남음", CreditFormat.percent(capRemainingPercent))
            if let capResetsAt {
                text += " · " + L10n.format("%@ 초기화", ResetSchedule(timestamp: capResetsAt, now: now, language: language).dateLabel)
            }
            return text
        }
        if let balance { return L10n.format("크레딧 잔액 %@", CreditFormat.compact(balance)) }
        return nil
    }
    /// Full sentence for tooltips, with exact credit counts.
    public func fullDescription(now: Date, burning: Bool, language: AppLanguage = L10n.language) -> String {
        var parts = [headline(burning: burning)]
        if let capUsed, let capLimit {
            parts.append(L10n.format("이번 달 %@ / %@ 크레딧 사용", CreditFormat.grouped(capUsed), CreditFormat.grouped(capLimit)))
        }
        if let capRemainingPercent { parts.append(L10n.format("크레딧 한도 %@ 남음", CreditFormat.percent(capRemainingPercent))) }
        if let capResetsAt { parts.append(ResetSchedule(timestamp: capResetsAt, now: now, language: language).compactLabel) }
        if capRemainingPercent == nil, let balance { parts.append(L10n.format("잔액 %@ 크레딧", CreditFormat.grouped(balance))) }
        return parts.joined(separator: " · ")
    }
}

extension UsageSnapshot {
    /// Nil while the plan allowance still covers usage.
    public func creditStatus(at date: Date = Date()) -> CreditStatus? {
        guard let limit else { return nil }
        let reason = limit.rateLimitReachedType.flatMap { $0.isEmpty ? nil : $0 }
        let blocked = reason != nil || limit.spendControlReached == true
        let window = preferredWindow
        let exhausted = (window?.usedPercent ?? 0) >= 100 && window?.resetPassed(at: date) != true
        let spending = !blocked && exhausted && limit.credits?.hasCredits == true
        guard blocked || spending else { return nil }
        let cap = limit.individualLimit
        return CreditStatus(kind: blocked ? .blocked : .spending,
                            blockedByCredits: limit.spendControlReached == true || reason?.contains("credits_depleted") == true,
                            capRemainingPercent: cap?.remainingPercent,
                            capUsed: cap?.used,
                            capLimit: cap?.limit,
                            capResetsAt: cap?.resetsAt,
                            balance: limit.credits?.balance)
    }

    /// Synthetic credit-mode reading for previews: a capped business seat or a personal balance.
    public static func creditDemo(profileID: String, business: Bool, now: Date = Date()) throws -> UsageSnapshot {
        var codex: [String: Any] = [
            "primary": ["usedPercent": 100, "windowDurationMins": 10080, "resetsAt": now.addingTimeInterval(4 * 86400).timeIntervalSince1970],
            "credits": ["hasCredits": true, "unlimited": false, "balance": business ? NSNull() : "2830"] as [String: Any]
        ]
        if business {
            codex["individualLimit"] = ["limit": "2500", "used": "1320", "remainingPercent": 47,
                                        "resetsAt": now.addingTimeInterval(13 * 86400).timeIntervalSince1970] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: ["rateLimitsByLimitId": ["codex": codex]])
        return try parse(data, profileID: profileID, plan: business ? "self_serve_business_prolite" : "plus", observedAt: now, isDemo: true)
    }
}

public enum CreditFormat {
    /// 850, 1K, 2.8K, 12K, 1.2M. Rounds down so a balance is never overstated.
    public static func compact(_ value: Double) -> String {
        guard value.isFinite, value >= 1 else { return "0" }
        let whole = Int(value.rounded(.down))
        func scaled(_ unit: Int, _ suffix: String) -> String {
            if whole >= unit * 10 { return "\(whole / unit)\(suffix)" }
            let tenths = whole / (unit / 10)
            return tenths % 10 == 0 ? "\(tenths / 10)\(suffix)" : "\(tenths / 10).\(tenths % 10)\(suffix)"
        }
        if whole < 1_000 { return String(whole) }
        if whole < 1_000_000 { return scaled(1_000, "K") }
        return scaled(1_000_000, "M")
    }
    public static func percent(_ value: Double) -> String {
        "\(Int(min(100, max(0, value.isFinite ? value : 0)).rounded(.down)))%"
    }
    /// 1,319 style, rounded down.
    public static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .down
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}

/// Detects whether credits went down since the previous reading of the same account.
public struct CreditBurnTracker {
    private var last: [String: Double] = [:]
    public init() {}
    public mutating func record(profileID: String, status: CreditStatus?) -> Bool {
        guard let status, status.kind == .spending, let meter = status.consumptionMeter else {
            last[profileID] = nil
            return false
        }
        defer { last[profileID] = meter }
        guard let previous = last[profileID] else { return false }
        return meter > previous + 0.0001
    }
}
