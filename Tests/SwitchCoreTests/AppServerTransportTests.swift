import XCTest
@testable import SwitchCore

/// Drives the transport against a fake `app-server` shell script with synthetic replies.
/// No real Codex binary, credential, or network is involved.
@MainActor
final class AppServerTransportTests: XCTestCase {
    var base: URL!
    var home: URL!
    var script: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        home = base.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        script = base.appendingPathComponent("fake-codex")
        let body = #"""
        #!/bin/sh
        mode=$(cat "$CODEX_HOME/fake-mode" 2>/dev/null || echo ok)
        home=$(cat "$CODEX_HOME/fake-home" 2>/dev/null || echo "$CODEX_HOME")
        while IFS= read -r raw; do
          line=$(printf '%s' "$raw" | sed 's#\\/#/#g')
          id=$(printf '%s' "$line" | sed -nE 's/.*"id":("[^"]*"|[0-9]+).*/\1/p')
          case "$line" in
            *'"initialize"'*) printf '{"id":%s,"result":{"codexHome":"%s","userAgent":"fake"}}\n' "$id" "$home" ;;
            *'"initialized"'*) ;;
            *'"account/read"'*) printf '{"id":%s,"result":{"account":{"type":"chatgpt","email":"synthetic@example.test","planType":"prolite"},"requiresOpenaiAuth":true}}\n' "$id" ;;
            *'"account/rateLimits/read"'*)
              case "$mode" in
                hang) sleep 3 ;;
                huge) printf '{"id":%s,"result":{"pad":"' "$id"; head -c 1100000 /dev/zero | tr '\0' 'x'; printf '"}}\n' ;;
                notify) printf '{"method":"account/updated","params":{}}\n'; printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":84,"windowDurationMins":10080}}}}\n' "$id" ;;
                *) printf '{"method":"remoteControl/status/changed","params":{}}\n'; printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":84,"windowDurationMins":10080,"resetsAt":1789816804},"secondary":null,"planType":"prolite"},"rateLimitsByLimitId":{"codex_other":{"primary":{"usedPercent":0,"windowDurationMins":300}},"codex":{"primary":{"usedPercent":84,"windowDurationMins":10080,"resetsAt":1789816804}}}}}\n' "$id" ;;
              esac ;;
          esac
        done
        """#
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: base) }
    func transport(idle: TimeInterval = 5) -> AppServerTransport {
        AppServerTransport(configuration: .init(executable: script, codexHome: home, clientName: "test", clientVersion: "0", idleTimeout: idle))
    }
    func mode(_ value: String) throws { try value.write(to: home.appendingPathComponent("fake-mode"), atomically: true, encoding: .utf8) }
    func settle(_ seconds: TimeInterval = 1.5) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func testReaderCompletesAndServerStopsOnClose() async throws {
        let transport = transport()
        let reading = try await CurrentAccountReader(transport: transport).read()
        XCTAssertEqual(reading.usage.limit?.primary?.remainingPercent, 16)
        XCTAssertEqual(reading.usage.limit?.primary?.resetsAt, 1_789_816_804)
        XCTAssertNil(reading.usage.limit?.secondary)
        XCTAssertEqual(reading.usage.plan, "prolite")
        XCTAssertTrue(transport.isRunning)
        transport.close()
        await settle()
        XCTAssertFalse(transport.isRunning)
    }
    func testIdleTimeoutStopsServerWithoutClose() async throws {
        let transport = transport(idle: 0.5)
        _ = try await transport.request(.identity, id: 1, timeout: 5)
        XCTAssertTrue(transport.isRunning)
        await settle()
        XCTAssertFalse(transport.isRunning)
    }
    func testTimeoutStopsServerAndReaderReportsRemoteFailure() async throws {
        try mode("hang")
        let transport = transport()
        _ = try await transport.request(.identity, id: 1, timeout: 5)
        let started = Date()
        do { _ = try await transport.request(.limits, id: 2, timeout: 0.5); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? AppServerTransportError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertFalse(transport.isRunning)
        // A later read relaunches the server instead of reusing the dead one.
        try mode("ok")
        let reading = try await CurrentAccountReader(transport: transport).read()
        XCTAssertEqual(reading.usage.limit?.primary?.remainingPercent, 16)
        transport.close()
    }
    func testOversizedReplyIsRejected() async throws {
        try mode("huge")
        let transport = transport()
        _ = try await transport.request(.identity, id: 1, timeout: 5)
        do { _ = try await transport.request(.limits, id: 2, timeout: 5); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? AppServerTransportError, .oversized) }
        XCTAssertFalse(transport.isRunning)
    }
    func testAccountChangeNotificationInvalidatesReading() async throws {
        try mode("notify")
        let transport = transport()
        do { _ = try await CurrentAccountReader(transport: transport).read(); XCTFail("Expected identity change") }
        catch { XCTAssertEqual(error as? AccountReadError, .identityChanged) }
        transport.close()
    }
    func testDifferentCredentialHomeIsRefused() async throws {
        try "/nonexistent/other-home".write(to: home.appendingPathComponent("fake-home"), atomically: true, encoding: .utf8)
        let transport = transport()
        do { _ = try await transport.request(.identity, id: 1, timeout: 5); XCTFail("Expected refusal") }
        catch { XCTAssertEqual(error as? AppServerTransportError, .homeMismatch) }
        XCTAssertFalse(transport.isRunning)
    }
    func testMissingExecutableFailsToLaunch() async {
        let transport = AppServerTransport(configuration: .init(executable: base.appendingPathComponent("missing"), codexHome: home, clientName: "test", clientVersion: "0"))
        do { _ = try await transport.request(.identity, id: 1, timeout: 5); XCTFail("Expected launch failure") }
        catch { XCTAssertEqual(error as? AppServerTransportError, .launchFailed) }
    }
    func testLocateSkipsMissingDirectoriesAndNonExecutables() throws {
        let plain = base.appendingPathComponent("plain")
        try Data("x".utf8).write(to: plain)
        XCTAssertNil(CodexExecutable.locate(candidates: [base.appendingPathComponent("missing"), home, plain], environment: [:]))
        XCTAssertEqual(CodexExecutable.locate(candidates: [plain, script], environment: [:]), script)
        XCTAssertEqual(CodexExecutable.locate(candidates: [plain], environment: ["CODEX_CLI_PATH": script.path]), script)
    }
    func testLimitsRequestSkipsResetCreditDetails() throws {
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: AccountReadRequest.limits.encoded(id: 3)) as? [String: Any])
        XCTAssertEqual((request["params"] as? [String: Bool])?["excludeResetCreditDetails"], true)
    }
}
