import AppKit
import SwiftUI
import SwitchCore

/// Claude usage for every account on the Claude tab, from files the Claude apps already write.
/// Read-only: no credentials, no network. The 5-hour reset is an estimate; a refusal recorded by
/// Claude Code gives the exact time a limit lifts.
@MainActor
final class ClaudeUsageBoard: ObservableObject {
    struct Entry: Equatable {
        var account: String?
        var estimate: ClaudeUsageEstimate?
        var block: ClaudeQuotaBlock?
        var isEmpty: Bool { estimate == nil && block == nil }
    }
    /// Keyed by desktop profile id; the desktop app's current account (saved or not) is `desktopCurrent`.
    @Published var desktopSaved: [String: Entry] = [:]
    @Published var desktopCurrent = Entry()
    /// Keyed by terminal profile id; the default `~/.claude` account is `cliDefault`.
    @Published var cliSaved: [String: Entry] = [:]
    @Published var cliDefault = Entry()

    private let scanner = ClaudeQuotaScanner()
    private(set) var settings: ClaudeUsageSettings?
    /// Reloads with the current account lists; set by the owner.
    var reload: () -> Void = {}

    func refresh(desktop: DesktopModel, cli: CLIModel, now: Date = Date()) {
        let desk = desktop.store
        let settings = ClaudeUsageSettings(file: desk.root.appendingPathComponent("usage-settings.json"))
        self.settings = settings

        // Desktop folders: the app's own folder for the current account, the store's folders for the rest.
        var folders: [(key: String?, folder: URL)] = [(nil, desk.active)]
        for profile in desktop.profiles where profile.id != desktop.activeID {
            if let folder = try? desk.folder(for: profile.id) { folders.append((profile.id, folder)) }
        }
        var history: [String: [ClaudeUsageSample]] = [:] // by account
        var desktopAccounts: [String?: String] = [:]
        for item in folders {
            guard let account = desk.accountID(inFolder: item.folder) else { continue }
            desktopAccounts[item.key] = account
            history[account, default: []] += ClaudeUsage.samples(inFolder: item.folder)
        }

        // Refusals by account: the desktop Code tab (since the last desktop switch), the default terminal
        // account, and each saved terminal account's own folder.
        var blocks: [String: ClaudeQuotaBlock] = [:]
        func add(_ block: ClaudeQuotaBlock?, to account: String?) {
            guard let block, let account else { return }
            if let known = blocks[account], known.resetsAt >= block.resetsAt { return }
            blocks[account] = block
        }
        let defaultFolder = cli.store.defaultConfig
        add(scanner.activeBlock(configFolder: defaultFolder, now: now, since: desk.lastSwitch) { $0 == "claude-desktop" },
            to: desktopAccounts[nil] ?? nil)
        let cliDefaultAccount = cli.store.account(of: nil)
        add(scanner.activeBlock(configFolder: defaultFolder, now: now) { $0 != "claude-desktop" }, to: cliDefaultAccount?.account)
        var cliAccounts: [String: (account: String, org: String?)] = [:]
        for profile in cli.profiles {
            guard let account = cli.store.account(of: profile.id) else { continue }
            cliAccounts[profile.id] = account
            if let folder = cli.store.configFolder(of: profile.id) { add(scanner.activeBlock(configFolder: folder, now: now), to: account.account) }
        }

        func entry(account: String?, org: String? = nil) -> Entry {
            guard let account else { return Entry() }
            let samples = history[account] ?? []
            let weekly = settings.weeklyReset(account: account)
            // A terminal account shows its own organization's record; a desktop one the most recent.
            let org = org.flatMap { wanted in samples.contains { $0.org == wanted } ? wanted : nil }
            return Entry(account: account, estimate: ClaudeUsage.estimate(samples, org: org, weekly: weekly, now: now), block: blocks[account])
        }
        desktopCurrent = entry(account: desktopAccounts[nil] ?? nil)
        desktopSaved = Dictionary(uniqueKeysWithValues: folders.compactMap { item in item.key.map { ($0, entry(account: desktopAccounts[item.key] ?? nil)) } })
        cliDefault = entry(account: cliDefaultAccount?.account, org: cliDefaultAccount?.org)
        cliSaved = cliAccounts.mapValues { entry(account: $0.account, org: $0.org) }
    }

    /// Asks for the weekly reset shown in Claude's Settings → Usage, e.g. Friday 11:00.
    func editWeeklyReset(account: String?) {
        guard let account, let settings else { return }
        let current = settings.weeklyReset(account: account)
        let alert = NSAlert()
        alert.messageText = L10n.text("주간 한도 초기화 시각")
        alert.informativeText = L10n.text("Claude 설정 → 사용량에 보이는 주간 재설정 요일과 시각을 입력하세요. 계정마다 한 번만 입력하면 됩니다.")
        let days = NSPopUpButton(frame: NSRect(x: 0, y: 2, width: 110, height: 26))
        let symbols = Self.weekdayFormatter.weekdaySymbols ?? []
        for name in symbols { days.addItem(withTitle: name) }
        days.selectItem(at: (current?.weekday ?? 6) - 1)
        let time = NSDatePicker(frame: NSRect(x: 120, y: 2, width: 100, height: 26))
        time.datePickerElements = .hourMinute
        time.datePickerStyle = .textFieldAndStepper
        time.timeZone = TimeZone(identifier: "Asia/Seoul")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        time.calendar = calendar
        time.dateValue = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: current?.hour ?? 11, minute: current?.minute ?? 0)) ?? Date()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 30))
        box.addSubview(days); box.addSubview(time)
        alert.accessoryView = box
        alert.addButton(withTitle: L10n.text("저장"))
        alert.addButton(withTitle: L10n.text("취소"))
        if current != nil { alert.addButton(withTitle: L10n.text("지우기")) }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let parts = calendar.dateComponents([.hour, .minute], from: time.dateValue)
            try? settings.setWeeklyReset(WeeklyReset(weekday: days.indexOfSelectedItem + 1, hour: parts.hour ?? 0, minute: parts.minute ?? 0), account: account)
        case .alertThirdButtonReturn:
            try? settings.setWeeklyReset(nil, account: account)
        default: return
        }
        reload()
    }

    nonisolated static var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.language == .english ? "en_US" : "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter
    }
}

/// Text for one account's Claude usage.
struct ClaudeUsageText {
    let entry: ClaudeUsageBoard.Entry
    let now: Date

    var blocked: Bool { entry.block != nil }
    /// "5시간 88% · 주간 80% 남음"
    /// Left percentages; a recorded refusal overrides the estimate for its window.
    var fiveHourLeft: Double? {
        if entry.block.map({ !$0.isWeekly }) == true { return 0 }
        return entry.estimate?.fiveHourLeft
    }
    var weeklyLeft: Double? {
        if entry.block?.isWeekly == true { return 0 }
        return entry.estimate?.weeklyLeft
    }
    /// "5시간 88% · 주간 80% 남음"
    var amounts: String? {
        guard let five = fiveHourLeft, let week = weeklyLeft else { return nil }
        return L10n.format("5시간 %@ · 주간 %@ 남음", Self.percent(five), Self.percent(week))
    }
    /// "5시간 88% 남음 · ~오후 2:50 초기화"
    var fiveHourLine: String? {
        guard let five = fiveHourLeft else { return nil }
        let reset = entry.block.map { $0.isWeekly ? nil : $0.resetsAt } ?? entry.estimate?.fiveHourReset
        return L10n.format("5시간 %@ 남음", Self.percent(five))
            + (reset.map { " · " + L10n.format("~%@ 초기화", Self.clock($0, now: now)) } ?? "")
    }
    /// "주간 80% 남음 · (금) 오전 11:00 초기화"
    var weeklyLine: String? {
        guard let week = weeklyLeft else { return nil }
        let reset = entry.block.flatMap { $0.isWeekly ? $0.resetsAt : nil } ?? entry.estimate?.weeklyReset
        return L10n.format("주간 %@ 남음", Self.percent(week))
            + (reset.map { " · " + L10n.format("%@ 초기화", Self.weekday($0)) } ?? "")
    }
    /// The limit that blocks requests, with the exact time it lifts.
    var blockLine: String? {
        guard let block = entry.block else { return nil }
        let window = block.isWeekly ? L10n.text("주간 한도") : L10n.text("5시간 한도")
        return L10n.format("%@ 도달 · %@ 풀림", window, Self.clock(block.resetsAt, now: now))
    }
    var age: String? { entry.estimate.map { Self.age($0.observed, now: now) } }
    /// Records older than this are called out, since the desktop app only records while it runs.
    var isStale: Bool { entry.estimate.map { now.timeIntervalSince($0.observed) > 30 * 60 } ?? false }
    var help: String {
        L10n.text("Claude 데스크톱 앱이 기록한 사용량입니다. 5시간 초기화 시각은 추정값이고, 주간 초기화는 직접 입력한 시각입니다. 한도에 걸리면 Claude Code 기록의 정확한 시각을 보여줍니다.")
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded(.down)))%" }
    static func clock(_ date: Date, now: Date) -> String {
        let formatter = ClaudeUsageBoard.weekdayFormatter
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let english = L10n.language == .english
        if calendar.isDate(date, inSameDayAs: now) { formatter.dateFormat = english ? "h:mm a" : "a h:mm" }
        else { formatter.dateFormat = english ? "EEE h:mm a" : "(E) a h:mm" }
        return formatter.string(from: date)
    }
    static func weekday(_ date: Date) -> String {
        let formatter = ClaudeUsageBoard.weekdayFormatter
        formatter.dateFormat = L10n.language == .english ? "EEE h:mm a" : "(E) a h:mm"
        return formatter.string(from: date)
    }
    static func age(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return L10n.text("방금 기록") }
        if minutes < 60 { return L10n.format("%@분 전 기록", String(minutes)) }
        if minutes < 48 * 60 { return L10n.format("%@시간 전 기록", String(minutes / 60)) }
        return L10n.format("%@일 전 기록", String(minutes / 1440))
    }
}

/// Usage under an account name: amounts, then resets or the blocking limit.
struct ClaudeUsageLines: View {
    let entry: ClaudeUsageBoard.Entry
    var compact = false

    var body: some View {
        let text = ClaudeUsageText(entry: entry, now: Date())
        VStack(alignment: .leading, spacing: 1) {
            if let block = text.blockLine {
                Label(block, systemImage: "hourglass").labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.warning).lineLimit(1)
            }
            if compact {
                if let amounts = text.amounts { line(amounts, primary: !text.blocked) }
            } else {
                if let five = text.fiveHourLine { line(five, primary: true) }
                if let week = text.weeklyLine { line(week, primary: true) }
                if text.isStale, let age = text.age {
                    Text(age).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }.help(([text.blockLine, text.fiveHourLine, text.weeklyLine, text.age].compactMap { $0 } + [text.help]).joined(separator: "\n"))
    }
    private func line(_ value: String, primary: Bool) -> some View {
        Text(value).font(.system(size: 11)).monospacedDigit().foregroundStyle(primary ? .primary : .secondary)
            .lineLimit(1).truncationMode(.tail)
    }
}
