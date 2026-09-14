import XCTest
@testable import SwitchCore

/// Drives the temporary-home login against fake `codex` scripts. No real login, browser, or credential.
@MainActor
final class TemporaryHomeLoginTests: XCTestCase {
    var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: base) }
    func script(_ name: String, _ body: String) throws -> URL {
        let url = base.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
    let synthetic = #"{"auth_mode":"chatgpt","tokens":{"account_id":"acct-b","access_token":"fake-access","refresh_token":"fake-refresh"}}"#

    func testReturnsCredentialsFromThrowawayHomeAndRemovesIt() async throws {
        let marker = base.appendingPathComponent("home-used")
        let exe = try script("codex-ok", """
        [ "$1" = login ] || exit 9
        printf '%s' "$CODEX_HOME" > "\(marker.path)"
        printf '%s' '\(synthetic)' > "$CODEX_HOME/auth.json"
        """)
        let data = try await TemporaryHomeLogin(executable: exe).run(timeout: 10)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), synthetic)
        XCTAssertEqual(try Identity(data: data).key.count, 64)
        let used = try String(contentsOf: marker)
        XCTAssertTrue(used.hasPrefix(FileManager.default.temporaryDirectory.path), used)
        XCTAssertFalse(used.contains("/.codex"), "must never touch the real credential home")
        XCTAssertFalse(FileManager.default.fileExists(atPath: used), "temporary home must be removed")
    }
    func testDeviceAuthFlagIsPassed() async throws {
        let exe = try script("codex-device", """
        [ "$2" = --device-auth ] || exit 9
        printf '%s' '\(synthetic)' > "$CODEX_HOME/auth.json"
        """)
        _ = try await TemporaryHomeLogin(executable: exe, deviceAuth: true).run(timeout: 10)
    }
    func testFailureAndMissingCredentialsAreReported() async throws {
        let failing = try script("codex-fail", "exit 3")
        do { _ = try await TemporaryHomeLogin(executable: failing).run(timeout: 10); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? TemporaryLoginError, .failed) }
        let empty = try script("codex-empty", "exit 0")
        do { _ = try await TemporaryHomeLogin(executable: empty).run(timeout: 10); XCTFail("Expected missing credentials") }
        catch { XCTAssertEqual(error as? TemporaryLoginError, .noCredentials) }
        let missing = TemporaryHomeLogin(executable: base.appendingPathComponent("nope"))
        do { _ = try await missing.run(timeout: 10); XCTFail("Expected launch failure") }
        catch { XCTAssertEqual(error as? TemporaryLoginError, .launchFailed) }
    }
    func testTimeoutTerminatesTheLogin() async throws {
        let exe = try script("codex-hang", "sleep 5")
        let login = TemporaryHomeLogin(executable: exe)
        let started = Date()
        do { _ = try await login.run(timeout: 0.5); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? TemporaryLoginError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertFalse(login.isRunning)
    }
    func testCancelStopsTheLogin() async throws {
        let exe = try script("codex-wait", "sleep 5")
        let login = TemporaryHomeLogin(executable: exe)
        let task = Task { try await login.run(timeout: 10) }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(login.isRunning)
        login.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? TemporaryLoginError, .cancelled) }
        XCTAssertFalse(login.isRunning)
    }
}
