import Foundation

/// All visible reset dates use Korea time, independent of the Mac's locale/timezone.
public struct ResetSchedule {
    public let dateLabel: String
    public let timeLabel: String
    public let remainingLabel: String
    public let fullLabel: String
    public let needsRefresh: Bool

    public init(timestamp: Double?, now: Date) {
        guard let timestamp, timestamp.isFinite, timestamp > 0,
              timestamp <= 253402300799 else {
            dateLabel = "초기화 날짜 미확인"
            timeLabel = ""
            remainingLabel = ""
            fullLabel = "초기화 시각을 확인하지 못했습니다."
            needsRefresh = false
            return
        }
        let date = Date(timeIntervalSince1970: timestamp)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: now) == calendar.component(.year, from: date) ? "M월 d일" : "yyyy년 M월 d일"
        let day = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            dateLabel = "오늘 · " + day
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            dateLabel = "내일 · " + day
        } else { dateLabel = day }
        formatter.dateFormat = "a h:mm"
        timeLabel = formatter.string(from: date) + " 초기화"
        formatter.dateFormat = "yyyy년 M월 d일 (EEEE) a h:mm:ss"
        fullLabel = formatter.string(from: date) + " · 한국 시간 (KST)"
        needsRefresh = date <= now
        if needsRefresh {
            remainingLabel = "시각 지남 · 새로고침 필요"
        } else {
            let seconds = date.timeIntervalSince(now)
            if seconds < 60 { remainingLabel = "1분 미만 남음" }
            else {
                let minutes = Int(ceil(seconds / 60))
                let days = minutes / 1440
                let hours = minutes % 1440 / 60
                let mins = minutes % 60
                if days > 0 { remainingLabel = "\(days)일" + (hours > 0 ? " \(hours)시간" : "") + " 남음" }
                else if hours > 0 { remainingLabel = "\(hours)시간" + (mins > 0 ? " \(mins)분" : "") + " 남음" }
                else { remainingLabel = "\(mins)분 남음" }
            }
        }
    }
}
