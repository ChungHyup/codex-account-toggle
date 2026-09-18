import XCTest
@testable import SwitchCore

final class SessionUsageTests: XCTestCase {
    var base: URL!
    var store: Store!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("codex/sessions/2026/09/11"), withIntermediateDirectories: true)
        store = Store(root: base.appendingPathComponent("profiles"), home: base.appendingPathComponent("codex"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: base) }

    func fixture(_ account: String) -> Data {
        Data("{\"auth_mode\":\"chatgpt\",\"tokens\":{\"account_id\":\"\(account)\",\"access_token\":\"fake-access\",\"refresh_token\":\"fake-refresh\"}}".utf8)
    }
    func tokenCount(_ stamp: String, used: Double = 48, plan: String = "self_serve_business_prolite", limitID: String = "codex") -> String {
        #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1}},"rate_limits":{"limit_id":"\#(limitID)","limit_name":null,"primary":{"used_percent":\#(used),"window_minutes":10080,"resets_at":1789625044},"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":null},"plan_type":"\#(plan)","rate_limit_reached_type":null}}}"#
    }
    let meta = #"{"timestamp":"2026-09-11T09:00:00.000Z","type":"session_meta","payload":{"id":"synthetic","timestamp":"2026-09-11T09:00:00.000Z","cwd":"/tmp","originator":"Codex Desktop"}}"#
    let message = #"{"timestamp":"2026-09-11T09:10:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"synthetic filler line for tail tests"}]}}"#
    @discardableResult func rollout(_ name: String, lines: [String], modified: Date) throws -> URL {
        let url = store.sessions.appendingPathComponent("2026/09/11/\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }
    func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    func testParsesSnakeCaseTokenCountLine() throws {
        let value = try XCTUnwrap(SessionUsageReader.observation(from: Data(tokenCount("2026-09-11T09:18:54.550Z").utf8), fallbackDate: at(0)))
        XCTAssertEqual(value.observedAt, ISO8601DateFormatter().date(from: "2026-09-11T09:18:54Z"))
        XCTAssertEqual(value.limit.primary?.remainingPercent, 52)
        XCTAssertEqual(value.limit.primary?.windowDurationMins, 10080)
        XCTAssertEqual(value.limit.primary?.resetsAt, 1_789_625_044)
        XCTAssertNil(value.limit.secondary)
        XCTAssertEqual(value.plan, "self_serve_business_prolite")
    }
    func testIgnoresOtherRecordsBucketsAndMissingLimits() {
        XCTAssertNil(SessionUsageReader.observation(from: Data(meta.utf8), fallbackDate: at(0)))
        XCTAssertNil(SessionUsageReader.observation(from: Data(message.utf8), fallbackDate: at(0)))
        XCTAssertNil(SessionUsageReader.observation(from: Data(tokenCount("2026-09-11T09:18:54.550Z", limitID: "other").utf8), fallbackDate: at(0)))
        XCTAssertNil(SessionUsageReader.observation(from: Data(#"{"type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":null}}"#.utf8), fallbackDate: at(0)))
        XCTAssertNil(SessionUsageReader.observation(from: Data("not json".utf8), fallbackDate: at(0)))
        let fallback = SessionUsageReader.observation(from: Data(#"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5}}}}"#.utf8), fallbackDate: at(77))
        XCTAssertEqual(fallback?.observedAt, at(77))
    }
    func testScanTakesLatestPerFileNewestFirstAndFallsBackPastTheTail() throws {
        try rollout("old", lines: [meta, tokenCount("2026-09-10T01:00:00.000Z", used: 10), tokenCount("2026-09-10T02:00:00.000Z", used: 20)] + Array(repeating: message, count: 400), modified: at(1_000))
        try rollout("new", lines: [meta, tokenCount("2026-09-11T01:00:00.000Z", used: 30)], modified: at(2_000))
        try rollout("none", lines: [meta, message], modified: at(3_000))
        let all = SessionUsageReader.scan(sessionsRoot: store.sessions, tailBytes: 4_096)
        XCTAssertEqual(all.map { $0.limit.primary?.usedPercent }, [30, 20])
        let limited = SessionUsageReader.scan(sessionsRoot: store.sessions, maxFiles: 2, tailBytes: 4_096)
        XCTAssertEqual(limited.map { $0.limit.primary?.usedPercent }, [30])
        XCTAssertTrue(SessionUsageReader.scan(sessionsRoot: base.appendingPathComponent("missing")).isEmpty)
    }
    func testCreditStateIsReadFromLocalRecords() throws {
        let capped = #"{"timestamp":"2026-09-18T04:28:23.203Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":100.0,"window_minutes":10080,"resets_at":1790064804},"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":null},"individual_limit":{"limit":"2500","used":"1508.2","remaining_percent":40,"resets_at":1790812800},"spend_control_reached":null,"plan_type":"self_serve_business_prolite","rate_limit_reached_type":null}}}"#
        let reading = try XCTUnwrap(SessionUsageReader.observation(from: Data(capped.utf8), fallbackDate: at(0)))
        XCTAssertEqual(reading.limit.credits?.hasCredits, true)
        XCTAssertNil(reading.limit.credits?.balance)
        XCTAssertEqual(reading.limit.individualLimit?.remainingPercent, 40)
        XCTAssertEqual(try XCTUnwrap(reading.limit.individualLimit?.used), 1508.2, accuracy: 0.001)
        let snapshot = UsageSnapshot(profileID: "b", plan: reading.plan, limit: reading.limit, observedAt: reading.observedAt, source: .sessionLog)
        XCTAssertEqual(snapshot.creditStatus(at: reading.observedAt)?.shortValue, "40%")
        // As recorded today: credits available but no per-seat cap in the local record.
        let uncapped = capped.replacingOccurrences(of: #"{"limit":"2500","used":"1508.2","remaining_percent":40,"resets_at":1790812800}"#, with: "null")
        let plain = try XCTUnwrap(SessionUsageReader.observation(from: Data(uncapped.utf8), fallbackDate: at(0)))
        let status = UsageSnapshot(profileID: "b", plan: plain.plan, limit: plain.limit, observedAt: plain.observedAt, source: .sessionLog).creditStatus(at: plain.observedAt)
        XCTAssertEqual(status?.kind, .spending)
        XCTAssertNil(status?.shortValue)
        // Cached readings keep the credit state across launches.
        let cached = try JSONDecoder().decode(SessionUsageObservation.self, from: JSONEncoder().encode(reading))
        XCTAssertEqual(cached, reading)
    }
    func testFreshLiveReadingIsNotReplacedByNewerLocalHistory() {
        let now = at(10_000)
        func snap(_ id: String, _ time: TimeInterval, _ source: UsageSource) -> UsageSnapshot {
            UsageSnapshot(profileID: id, plan: nil, limit: nil, observedAt: at(time), source: source)
        }
        let shown = ["a": snap("a", 9_900, .live), "b": snap("b", 9_000, .live), "c": snap("c", 9_900, .live), "d": snap("d", 9_900, .demo)]
        let history = ["a": snap("a", 9_990, .sessionLog), "b": snap("b", 9_990, .sessionLog), "c": snap("c", 5_000, .sessionLog), "e": snap("e", 1, .sessionLog)]
        let merged = SessionUsage.merge(history: history, shown: shown, now: now)
        XCTAssertEqual(merged["a"]?.source, .live, "fresh live wins even though Codex wrote a newer local line")
        XCTAssertEqual(merged["b"]?.source, .sessionLog, "stale live gives way to newer history")
        XCTAssertEqual(merged["c"]?.source, .live, "older history never replaces live")
        XCTAssertNil(merged["d"], "only live readings are carried over")
        XCTAssertEqual(merged["e"]?.source, .sessionLog)
    }
    func testInvalidDurationDoesNotCrash() {
        let line = Data(#"{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5,"window_minutes":1e100}}}}"#.utf8)
        let value = SessionUsageReader.observation(from: line, fallbackDate: at(1))
        XCTAssertNil(value?.limit.primary?.windowDurationMins)
    }
    func testAttributionRules() {
        XCTAssertNil(UsageAttributor(points: []).profileID(at: at(50)))
        let saved = UsageAttributor(points: [IdentityPoint(at: at(100), id: "a", kind: .saved)])
        XCTAssertNil(saved.profileID(at: at(50)))
        XCTAssertEqual(saved.profileID(at: at(150)), "a")
        let switched = UsageAttributor(points: [IdentityPoint(at: at(200), id: "b", kind: .switched), IdentityPoint(at: at(100), id: "a", kind: .saved)])
        XCTAssertEqual(switched.profileID(at: at(150)), "a")
        XCTAssertEqual(switched.profileID(at: at(200)), "b")
        XCTAssertEqual(switched.profileID(at: at(250)), "b")
        let manual = UsageAttributor(points: [IdentityPoint(at: at(100), id: "a", kind: .saved), IdentityPoint(at: at(200), id: "b", kind: .observed)])
        XCTAssertNil(manual.profileID(at: at(150)))
        XCTAssertNil(manual.profileID(at: at(50)))
        XCTAssertEqual(manual.profileID(at: at(250)), "b")
        let onlySwitch = UsageAttributor(points: [IdentityPoint(at: at(200), id: "b", kind: .switched)])
        XCTAssertNil(onlySwitch.profileID(at: at(150)))
        XCTAssertEqual(onlySwitch.profileID(at: at(300)), "b")
    }
    func testCollectAttributesCachesAndKeepsReadingsAfterLogsDisappear() throws {
        let a = try store.save(data: fixture("a"), name: "A")
        let b = try store.save(data: fixture("b"), name: "B")
        try store.note(identity: a.id, kind: .saved, at: at(1_000))
        try store.note(identity: b.id, kind: .switched, at: at(2_000))
        let first = try rollout("a-session", lines: [meta, tokenCount("1970-01-01T00:20:00.000Z", used: 40)], modified: at(1_500))
        try rollout("b-session", lines: [meta, tokenCount("1970-01-01T00:41:40.000Z", used: 70)], modified: at(2_600))
        var usage = SessionUsage.collect(store: store, profileIDs: [a.id, b.id])
        XCTAssertEqual(usage[a.id]?.limit?.primary?.remainingPercent, 60)
        XCTAssertEqual(usage[b.id]?.limit?.primary?.remainingPercent, 30)
        XCTAssertEqual(usage[a.id]?.source, .sessionLog)
        XCTAssertFalse(usage[a.id]!.isDemo)
        XCTAssertFalse(usage[a.id]!.isStale(at: Date()))
        XCTAssertEqual(usage[a.id]?.planLabel, "Business 5x")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.root.appendingPathComponent("usage.json").path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try FileManager.default.removeItem(at: first)
        usage = SessionUsage.collect(store: store, profileIDs: [a.id, b.id])
        XCTAssertEqual(usage[a.id]?.limit?.primary?.remainingPercent, 60)
        try rollout("a-older", lines: [meta, tokenCount("1970-01-01T00:18:00.000Z", used: 90)], modified: at(1_100))
        usage = SessionUsage.collect(store: store, profileIDs: [a.id, b.id])
        XCTAssertEqual(usage[a.id]?.limit?.primary?.remainingPercent, 60)
        XCTAssertNil(SessionUsage.collect(store: store, profileIDs: ["unknown"])["unknown"])
    }
    func testObservedPointsAreThrottledAndPrivate() throws {
        try store.note(identity: "a", kind: .observed, at: at(0))
        try store.note(identity: "a", kind: .observed, at: at(60))
        try store.note(identity: "a", kind: .observed, at: at(4_000))
        try store.note(identity: "b", kind: .observed, at: at(4_010))
        try store.note(identity: "a", kind: .saved, at: at(4_020))
        XCTAssertEqual(try store.identityPoints().map { "\($0.kind.rawValue):\($0.id)@\(Int($0.at.timeIntervalSince1970))" },
                       ["observed:a@0", "observed:a@4000", "observed:b@4010", "saved:a@4020"])
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.root.appendingPathComponent("identity-points.json").path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testPlanLabelHumanizesServicePlans() {
        func label(_ plan: String) -> String { UsageSnapshot(profileID: "x", plan: plan, limit: nil, observedAt: Date(), source: .sessionLog).planLabel }
        XCTAssertEqual(label("prolite"), "Pro 5x")
        XCTAssertEqual(label("pro"), "Pro 20x")
        XCTAssertEqual(label("plus"), "Plus")
        XCTAssertEqual(label("self_serve_business_prolite"), "Business 5x")
        XCTAssertEqual(label("ent26"), "Enterprise")
        XCTAssertEqual(label("enterprise_cbp_usage_based"), "Enterprise")
        XCTAssertEqual(label("edu_pro"), "Edu Pro")
        XCTAssertEqual(label("unknown"), L10n.text("요금제 미확인"))
    }
}
