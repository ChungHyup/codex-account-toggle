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
