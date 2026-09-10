import XCTest
@testable import SwitchCore

final class LocalizationTests: XCTestCase {
    func testBothCatalogsHaveSameKeysAndPlaceholders() {
        let korean = L10n.catalog(for: .korean)
        let english = L10n.catalog(for: .english)
        XCTAssertGreaterThan(korean.count, 90)
        XCTAssertEqual(Set(korean.keys), Set(english.keys))
        for key in korean.keys {
            XCTAssertFalse(english[key]!.isEmpty, key)
            XCTAssertEqual(korean[key]!.components(separatedBy: "%@").count,
                           english[key]!.components(separatedBy: "%@").count, key)
        }
        XCTAssertEqual(L10n.text("계정 전환", language: .english), "Switch account")
    }
    func testEnglishDatesKeepKoreaTimezone() {
        let date = ISO8601DateFormatter().date(from: "2026-09-10T15:05:00Z")!
        let value = ResetSchedule(timestamp: date.timeIntervalSince1970, now: date.addingTimeInterval(-600), language: .english)
        XCTAssertEqual(value.dateLabel, "Tomorrow · Sep 11")
        XCTAssertEqual(value.timeLabel, "Resets 12:05 AM")
        XCTAssertEqual(value.remainingLabel, "10m left")
        XCTAssertTrue(value.fullLabel.contains("KST"))
    }
    func testWeeklyOnlyDoesNotCreateSecondWindow() throws {
        let snapshot = try UsageSnapshot.parse(Data(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":26,"windowDurationMins":10080},"secondary":null}}}"#.utf8), profileID: "synthetic", plan: "prolite", observedAt: Date())
        XCTAssertEqual(snapshot.limit?.primary?.remainingPercent, 74)
        XCTAssertNil(snapshot.limit?.secondary)
    }
}
