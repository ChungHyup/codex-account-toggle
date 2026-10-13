import XCTest
@testable import SwitchCore

/// Synthetic usage history and transcripts in temporary folders only.
final class ClaudeUsageTests: XCTestCase {
    var dir: URL!
    let base = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")! // Tue 09:00 KST
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: dir) }

    func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    func sample(_ minutes: Double, _ five: Double, _ week: Double, org: String = "org-a") -> ClaudeUsageSample {
        ClaudeUsageSample(org: org, time: at(minutes), fiveHour: five, weekly: week)
    }

    func testReadsDesktopHistory() throws {
        let json = #"{"version":1,"samples":[{"org":"org-a","t":1792022400000,"u":{"fh":3,"sd":20}},{"org":"org-b","t":1792023300000,"u":{"fh":0,"sd":0}},{"bad":1}]}"#
        try Data(json.utf8).write(to: dir.appendingPathComponent(ClaudeUsage.historyFile))
        let samples = ClaudeUsage.samples(inFolder: dir)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0], ClaudeUsageSample(org: "org-a", time: Date(timeIntervalSince1970: 1792022400), fiveHour: 3, weekly: 20))
        XCTAssertEqual(ClaudeUsage.latestOrg(samples), "org-b")
        XCTAssertTrue(ClaudeUsage.samples(inFolder: dir.appendingPathComponent("missing")).isEmpty)
    }

    func testFiveHourResetIsEstimatedFromWindowStart() {
        // Empty at 0, used by 15 → the window started around 7.5 minutes in.
        let samples = [sample(0, 0, 10), sample(15, 4, 11), sample(30, 9, 12), sample(60, 12, 13), sample(61, 50, 50, org: "org-b")]
        let estimate = ClaudeUsage.estimate(samples, org: "org-a", weekly: nil, now: at(90))!
        XCTAssertEqual(estimate.fiveHourUsed, 12)
        XCTAssertEqual(estimate.fiveHourLeft, 88)
        XCTAssertEqual(estimate.fiveHourReset, at(7.5 + 300))
        XCTAssertEqual(estimate.weeklyUsed, 13)
        XCTAssertNil(estimate.weeklyReset)
        XCTAssertEqual(estimate.observed, at(60))
        // Without an org, the most recently recorded one is shown.
        XCTAssertEqual(ClaudeUsage.estimate(samples, weekly: nil, now: at(90))?.org, "org-b")
    }

    func testGapOrDropStartsANewWindow() {
        // First record after a long gap: start at that record. A later drop means a new window.
        let gap = [sample(0, 0, 1), sample(120, 6, 2), sample(135, 8, 2)]
        XCTAssertEqual(ClaudeUsage.estimate(gap, weekly: nil, now: at(140))?.fiveHourReset, at(120 + 300))
        let drop = [sample(0, 30, 5), sample(15, 35, 6), sample(330, 2, 7), sample(345, 5, 7)]
        XCTAssertEqual(ClaudeUsage.estimate(drop, weekly: nil, now: at(350))?.fiveHourReset, at(330 + 300))
    }

    func testExpiredWindowShowsFullAllowance() {
        let samples = [sample(0, 0, 10), sample(15, 40, 30)]
        let later = ClaudeUsage.estimate(samples, weekly: nil, now: at(7.5 + 301))!
        XCTAssertEqual(later.fiveHourUsed, 0)
        XCTAssertNil(later.fiveHourReset)
        XCTAssertEqual(later.weeklyUsed, 30)
    }

    func testWeeklySettingResetsWeeklyUsage() throws {
        // Friday 11:00 KST.
        let friday = try XCTUnwrap(WeeklyReset(weekday: 6, hour: 11, minute: 0))
        let next = friday.next(after: base)
        XCTAssertEqual(next, ISO8601DateFormatter().date(from: "2026-10-16T02:00:00Z"))
        XCTAssertEqual(friday.previous(atOrBefore: base), ISO8601DateFormatter().date(from: "2026-10-09T02:00:00Z"))
        let samples = [sample(0, 0, 80)]
        XCTAssertEqual(ClaudeUsage.estimate(samples, weekly: friday, now: at(60))?.weeklyUsed, 80)
        XCTAssertEqual(ClaudeUsage.estimate(samples, weekly: friday, now: at(60))?.weeklyReset, next)
        let afterReset = next.addingTimeInterval(60)
        XCTAssertEqual(ClaudeUsage.estimate(samples, weekly: friday, now: afterReset)?.weeklyUsed, 0)
        XCTAssertNil(WeeklyReset(weekday: 8, hour: 1, minute: 0))
    }

    func transcript(_ lines: [String], name: String = "s.jsonl", in config: URL) throws -> URL {
        let folder = config.appendingPathComponent("projects/-tmp-project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }
    func refusal(at date: Date, resets: Date, window: String = "five_hour", entry: String = "cli") -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        return #"{"type":"assistant","timestamp":"\#(stamp)","entrypoint":"\#(entry)","error":"rate_limit","quotaLimits":{"status":"rejected","resetsAt":\#(Int(resets.timeIntervalSince1970)),"rateLimitType":"\#(window)"}}"#
    }

    func testFindsActiveRefusalInTranscripts() throws {
        let config = dir.appendingPathComponent("config")
        let now = Date()
        _ = try transcript([
            #"{"type":"user","timestamp":"2026-10-13T00:00:00Z"}"#,
            refusal(at: now.addingTimeInterval(-600), resets: now.addingTimeInterval(-60)), // already lifted
            refusal(at: now.addingTimeInterval(-300), resets: now.addingTimeInterval(3600)),
            #"{"quotaLimits":{"status":"allowed","resetsAt":1}}"#,
        ], in: config)
        _ = try transcript([refusal(at: now.addingTimeInterval(-120), resets: now.addingTimeInterval(86400), window: "seven_day", entry: "claude-desktop")],
                           name: "d.jsonl", in: config)
        let scanner = ClaudeQuotaScanner()
        let any = try XCTUnwrap(scanner.activeBlock(configFolder: config, now: now))
        XCTAssertEqual(any.window, "seven_day")
        XCTAssertTrue(any.isWeekly)
        let terminal = try XCTUnwrap(scanner.activeBlock(configFolder: config, now: now) { $0 != "claude-desktop" })
        XCTAssertEqual(terminal.window, "five_hour")
        XCTAssertEqual(terminal.resetsAt.timeIntervalSince1970, (now.addingTimeInterval(3600).timeIntervalSince1970).rounded(.down), accuracy: 1)
        // Refusals recorded before an account change do not count.
        XCTAssertNil(scanner.activeBlock(configFolder: config, now: now, since: now.addingTimeInterval(-60)))
        XCTAssertNil(scanner.activeBlock(configFolder: dir.appendingPathComponent("none"), now: now))
    }

    func testSettingsRoundTrip() throws {
        let settings = ClaudeUsageSettings(file: dir.appendingPathComponent("store/usage-settings.json"))
        XCTAssertNil(settings.weeklyReset(account: "acct"))
        let value = WeeklyReset(weekday: 6, hour: 11, minute: 0)
        try settings.setWeeklyReset(value, account: "acct")
        XCTAssertEqual(settings.weeklyReset(account: "acct"), value)
        try settings.setWeeklyReset(nil, account: "acct")
        XCTAssertNil(settings.weeklyReset(account: "acct"))
    }

    func testCLIAccountIDs() throws {
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": "acct-1", "organizationUuid": "org-1", "emailAddress": "a@example.test"]])
            .write(to: home.appendingPathComponent(".claude.json"))
        let store = CLIProfileStore(base: home.appendingPathComponent(".codex-account-toggle/claude-cli"), home: home)
        XCTAssertEqual(store.account(of: nil)?.account, "acct-1")
        XCTAssertEqual(store.account(of: nil)?.org, "org-1")
        XCTAssertEqual(store.email(of: nil), "a@example.test")
        XCTAssertEqual(store.configFolder(of: nil), home.appendingPathComponent(".claude"))
    }
}
