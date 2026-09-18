import XCTest
@testable import SwitchCore

final class CreditTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// The shape observed from account/rateLimits/read on a business seat past its weekly limit.
    func business(used: String = "1319.6232262849808", remaining: Int = 47, weeklyUsed: Int = 100, reached: String? = nil, spendReached: Bool = false) throws -> UsageSnapshot {
        let json = """
        {"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(weeklyUsed),"windowDurationMins":10080,"resetsAt":1790064804},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":null},"individualLimit":{"limit":"2500","used":"\(used)","remainingPercent":\(remaining),"resetsAt":1790812800},"spendControlReached":\(spendReached),"planType":"self_serve_business_prolite","rateLimitReachedType":\(reached.map { "\"\($0)\"" } ?? "null")},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":\(weeklyUsed),"windowDurationMins":10080,"resetsAt":1790064804},"secondary":null,"credits":{"hasCredits":true,"unlimited":false,"balance":null},"individualLimit":{"limit":"2500","used":"\(used)","remainingPercent":\(remaining),"resetsAt":1790812800},"spendControlReached":\(spendReached),"planType":"self_serve_business_prolite","rateLimitReachedType":\(reached.map { "\"\($0)\"" } ?? "null")}}}
        """
        return try UsageSnapshot.parse(Data(json.utf8), profileID: "b", plan: nil, observedAt: now, source: .live)
    }
    func personal(balance: String, hasCredits: Bool = true, weeklyUsed: Int = 100, reached: String? = nil) throws -> UsageSnapshot {
        let json = """
        {"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":\(weeklyUsed),"windowDurationMins":10080,"resetsAt":1790064804},"credits":{"hasCredits":\(hasCredits),"unlimited":false,"balance":"\(balance)"},"individualLimit":null,"rateLimitReachedType":\(reached.map { "\"\($0)\"" } ?? "null")}}}
        """
        return try UsageSnapshot.parse(Data(json.utf8), profileID: "p", plan: "plus", observedAt: now, source: .live)
    }

    func testCompactCounts() {
        let cases: [(Double, String)] = [(0, "0"), (0.9, "0"), (-5, "0"), (.nan, "0"), (7, "7"), (999.9, "999"), (1000, "1K"),
                                          (2000, "2K"), (2300, "2.3K"), (2830, "2.8K"), (2999, "2.9K"), (9999, "9.9K"),
                                          (10_000, "10K"), (12_345, "12K"), (999_999, "999K"), (1_000_000, "1M"), (1_250_000, "1.2M"), (15_000_000, "15M")]
        for (value, expected) in cases { XCTAssertEqual(CreditFormat.compact(value), expected, "\(value)") }
        XCTAssertEqual(CreditFormat.percent(47.9), "47%")
        XCTAssertEqual(CreditFormat.percent(120), "100%")
        XCTAssertEqual(CreditFormat.grouped(1319.62), "1,319")
    }
    func testBusinessSeatShowsRemainingCapPercent() throws {
        let status = try XCTUnwrap(try business().creditStatus(at: now))
        XCTAssertEqual(status.kind, .spending)
        XCTAssertEqual(status.shortValue, "47%")
        XCTAssertEqual(try XCTUnwrap(status.capUsed), 1319.62, accuracy: 0.01)
        XCTAssertEqual(status.capLimit, 2500)
        XCTAssertNil(status.balance)
        XCTAssertEqual(status.detail(now: now), L10n.format("크레딧 한도 %@ 남음", "47%") + " · " + L10n.format("%@ 초기화", ResetSchedule(timestamp: 1790812800, now: now, language: L10n.language).dateLabel))
        XCTAssertTrue(status.fullDescription(now: now, burning: true).contains("1,319 / 2,500"))
    }
    func testPersonalAccountShowsCompactBalance() throws {
        XCTAssertEqual(try personal(balance: "2830").creditStatus(at: now)?.shortValue, "2.8K")
        XCTAssertEqual(try personal(balance: "850.4").creditStatus(at: now)?.shortValue, "850")
        XCTAssertEqual(try personal(balance: "2830").creditStatus(at: now)?.detail(now: now), L10n.format("크레딧 잔액 %@", "2.8K"))
    }
    func testNoCreditModeWhileAllowanceRemainsOrWithoutCredits() throws {
        XCTAssertNil(try business(weeklyUsed: 84).creditStatus(at: now))
        XCTAssertNil(try personal(balance: "0", hasCredits: false).creditStatus(at: now))
        // After the weekly reset time the old 100% no longer means credits are in use.
        XCTAssertNil(try business().creditStatus(at: Date(timeIntervalSince1970: 1_790_064_805)))
        XCTAssertNil(try UsageSnapshot.demo(profileID: "d", index: 0, now: now).creditStatus(at: now))
    }
    func testBlockedStates() throws {
        let depleted = try XCTUnwrap(try business(remaining: 0, reached: "workspace_member_credits_depleted").creditStatus(at: now))
        XCTAssertEqual(depleted.kind, .blocked)
        XCTAssertTrue(depleted.blockedByCredits)
        XCTAssertEqual(depleted.headline(burning: true), L10n.text("크레딧 소진 · 사용이 중지됨"))
        let capped = try XCTUnwrap(try business(spendReached: true).creditStatus(at: now))
        XCTAssertTrue(capped.blockedByCredits)
        let limited = try XCTUnwrap(try personal(balance: "0", hasCredits: false, reached: "rate_limit_reached").creditStatus(at: now))
        XCTAssertEqual(limited.kind, .blocked)
        XCTAssertFalse(limited.blockedByCredits)
        XCTAssertEqual(limited.shortValue, "0")
    }
    func testBurnTrackerNeedsARisingMeter() throws {
        var tracker = CreditBurnTracker()
        XCTAssertFalse(tracker.record(profileID: "b", status: try business(used: "1319.6").creditStatus(at: now)), "first reading has no baseline")
        XCTAssertTrue(tracker.record(profileID: "b", status: try business(used: "1321.0").creditStatus(at: now)))
        XCTAssertFalse(tracker.record(profileID: "b", status: try business(used: "1321.0").creditStatus(at: now)), "idle in credit mode")
        XCTAssertFalse(tracker.record(profileID: "b", status: try business(used: "3").creditStatus(at: now)), "monthly cap reset")
        XCTAssertFalse(tracker.record(profileID: "p", status: try personal(balance: "2830").creditStatus(at: now)))
        XCTAssertTrue(tracker.record(profileID: "p", status: try personal(balance: "2790").creditStatus(at: now)), "balance went down")
        XCTAssertFalse(tracker.record(profileID: "p", status: nil), "left credit mode")
        XCTAssertFalse(tracker.record(profileID: "p", status: try personal(balance: "2700").creditStatus(at: now)), "baseline cleared")
    }
    func testOldCachedReadingsStillDecode() throws {
        let old = try JSONDecoder().decode(UsageLimit.self, from: Data(#"{"planType":"plus","primary":{"usedPercent":10,"windowDurationMins":10080}}"#.utf8))
        XCTAssertNil(old.credits)
        XCTAssertNil(old.individualLimit)
        let roundTrip = try JSONDecoder().decode(UsageLimit.self, from: JSONEncoder().encode(try business().limit!))
        XCTAssertEqual(roundTrip, try business().limit!)
    }
    func testPreviewFixturesMatchBothFormats() throws {
        XCTAssertEqual(try UsageSnapshot.creditDemo(profileID: "b", business: true, now: now).creditStatus(at: now)?.shortValue, "47%")
        XCTAssertEqual(try UsageSnapshot.creditDemo(profileID: "p", business: false, now: now).creditStatus(at: now)?.shortValue, "2.8K")
    }
}
