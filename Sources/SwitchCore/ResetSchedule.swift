import Foundation

/// All visible reset dates use Korea time, independent of the Mac's locale/timezone.
public struct ResetSchedule {
    public let dateLabel: String
    public let timeLabel: String
    public let remainingLabel: String
    public let fullLabel: String
    public let needsRefresh: Bool

    public init(timestamp: Double?, now: Date, language: AppLanguage = .korean) {
        let english = language == .english
        guard let timestamp, timestamp.isFinite, timestamp > 0,
              timestamp <= 253402300799 else {
            dateLabel = english ? "Reset date unavailable" : "초기화 날짜 미확인"
            timeLabel = ""
            remainingLabel = ""
            fullLabel = english ? "Reset time is unavailable." : "초기화 시각을 확인하지 못했습니다."
            needsRefresh = false
            return
        }
        let date = Date(timeIntervalSince1970: timestamp)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: english ? "en_US" : "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: now) == calendar.component(.year, from: date) ? (english ? "MMM d" : "M월 d일") : (english ? "MMM d, yyyy" : "yyyy년 M월 d일")
        let day = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            dateLabel = (english ? "Today · " : "오늘 · ") + day
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            dateLabel = (english ? "Tomorrow · " : "내일 · ") + day
        } else { dateLabel = day }
        formatter.dateFormat = english ? "h:mm a" : "a h:mm"
        timeLabel = (english ? "Resets " : "") + formatter.string(from: date) + (english ? "" : " 초기화")
        formatter.dateFormat = english ? "EEEE, MMM d, yyyy h:mm:ss a" : "yyyy년 M월 d일 (EEEE) a h:mm:ss"
        fullLabel = formatter.string(from: date) + (english ? " · Korea time (KST)" : " · 한국 시간 (KST)")
        needsRefresh = date <= now
        if needsRefresh {
            remainingLabel = english ? "Reset passed · Refresh needed" : "시각 지남 · 새로고침 필요"
        } else {
            let seconds = date.timeIntervalSince(now)
            if seconds < 60 { remainingLabel = english ? "Less than 1m left" : "1분 미만 남음" }
            else {
                let minutes = Int(ceil(seconds / 60))
                let days = minutes / 1440
                let hours = minutes % 1440 / 60
                let mins = minutes % 60
                if english {
                    if days > 0 { remainingLabel = "\(days)d \(hours)h left" }
                    else if hours > 0 { remainingLabel = "\(hours)h \(mins)m left" }
                    else { remainingLabel = "\(mins)m left" }
                } else if days > 0 { remainingLabel = "\(days)일" + (hours > 0 ? " \(hours)시간" : "") + " 남음" }
                else if hours > 0 { remainingLabel = "\(hours)시간" + (mins > 0 ? " \(mins)분" : "") + " 남음" }
                else { remainingLabel = "\(mins)분 남음" }
            }
        }
    }
}
