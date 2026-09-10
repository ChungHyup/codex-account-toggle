import XCTest
@testable import SwitchCore

final class UsageTests: XCTestCase {
    func parse(_ json: String) throws -> UsageSnapshot {
        try UsageSnapshot.parse(Data(json.utf8), profileID: "fixture", plan: nil, observedAt: Date(timeIntervalSince1970: 100))
    }
    func testRemainingIsInverseOfUsage() throws {
        let value = try parse(#"{"rateLimits":{"primary":{"usedPercent":28,"windowDurationMins":300}}}"#)
        XCTAssertEqual(value.limit?.primary?.remainingPercent, 72)
        XCTAssertEqual(value.limit?.primary?.title, "5시간")
    }
    func testMissingIsNotZeroOrFull() throws {
        let value = try parse(#"{"rateLimits":{"primary":{"usedPercent":null}}}"#)
        XCTAssertNil(value.limit?.primary?.remainingPercent)
        XCTAssertEqual(value.planLabel, "요금제 미확인")
    }
    func testMultipleBucketViewTakesPrecedence() throws {
        let value = try parse(#"{"rateLimits":{"primary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":80}}}}"#)
        XCTAssertEqual(value.limit?.primary?.remainingPercent, 20)
    }
    func testOtherBucketIsNotPresentedAsCodex() throws {
        let value = try parse(#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":5}}}}"#)
        XCTAssertNil(value.limit)
    }
    func testClampAndExpiredReset() throws {
        let value = try parse(#"{"rateLimits":{"primary":{"usedPercent":105,"resetsAt":110},"secondary":{"usedPercent":-10,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(value.limit?.primary?.remainingPercent, 0)
        XCTAssertEqual(value.limit?.secondary?.remainingPercent, 100)
        XCTAssertEqual(value.limit?.secondary?.title, "주간")
        XCTAssertTrue(value.limit!.primary!.resetPassed(at: Date(timeIntervalSince1970: 120)))
        XCTAssertTrue(value.isStale(at: Date(timeIntervalSince1970: 500)))
    }
}
