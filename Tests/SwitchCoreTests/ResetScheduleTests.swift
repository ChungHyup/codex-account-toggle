import XCTest
@testable import SwitchCore

final class ResetScheduleTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testTodayUsesKoreanTimeAndExactClock() {
        let value = ResetSchedule(timestamp: date("2026-09-10T14:30:00Z").timeIntervalSince1970, now: date("2026-09-10T12:10:00Z"))
        XCTAssertEqual(value.dateLabel, "오늘 · 9월 10일")
        XCTAssertEqual(value.timeLabel, "오후 11:30 초기화")
        XCTAssertEqual(value.remainingLabel, "2시간 20분 남음")
        XCTAssertTrue(value.fullLabel.contains("한국 시간 (KST)"))
    }
    func testMidnightCrossingIsTomorrowInKorea() {
        let value = ResetSchedule(timestamp: date("2026-09-10T15:05:00Z").timeIntervalSince1970, now: date("2026-09-10T14:55:00Z"))
        XCTAssertEqual(value.dateLabel, "내일 · 9월 11일")
        XCTAssertEqual(value.timeLabel, "오전 12:05 초기화")
        XCTAssertEqual(value.remainingLabel, "10분 남음")
    }
    func testNextYearIncludesYear() {
        let value = ResetSchedule(timestamp: date("2026-12-31T15:00:00Z").timeIntervalSince1970, now: date("2026-12-31T14:30:00Z"))
        XCTAssertEqual(value.dateLabel, "내일 · 2027년 1월 1일")
    }
    func testExpiredDoesNotClaimRefilledQuota() {
        let now = date("2026-09-10T12:00:00Z")
        let value = ResetSchedule(timestamp: now.timeIntervalSince1970, now: now)
        XCTAssertTrue(value.needsRefresh)
        XCTAssertEqual(value.remainingLabel, "시각 지남 · 새로고침 필요")
    }
    func testUnknownAndInvalidDatesStayUnknown() {
        for timestamp in [nil, Double.nan, Double.infinity, -1, 0, 1e20] as [Double?] {
            let value = ResetSchedule(timestamp: timestamp, now: Date())
            XCTAssertEqual(value.dateLabel, "초기화 날짜 미확인")
            XCTAssertEqual(value.timeLabel, "")
        }
    }
    func testSubMinuteAndWeeklyCountdown() {
        let now = date("2026-09-10T12:00:00Z")
        XCTAssertEqual(ResetSchedule(timestamp: now.addingTimeInterval(20).timeIntervalSince1970, now: now).remainingLabel, "1분 미만 남음")
        let week = ResetSchedule(timestamp: now.addingTimeInterval(3 * 86400 + 7200).timeIntervalSince1970, now: now)
        XCTAssertEqual(week.dateLabel, "9월 13일")
        XCTAssertEqual(week.remainingLabel, "3일 2시간 남음")
    }
}
