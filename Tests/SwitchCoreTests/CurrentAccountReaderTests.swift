import XCTest
@testable import SwitchCore

@MainActor
private final class FakeAccountTransport: CurrentAccountTransport {
    var calls: [AccountReadRequest] = []
    var revision = UUID()
    var fail = false
    var changeIdentity = false
    var signedOut = false
    var wrongID = false
    var nullEmail = false
    func request(_ request: AccountReadRequest, id: Int, timeout: TimeInterval) async throws -> AccountReadReply {
        calls.append(request)
        XCTAssertEqual(timeout, 10)
        if fail { throw NSError(domain: "SECRET-SHOULD-NOT-LEAK", code: 401) }
        if changeIdentity && request == .limits { revision = UUID() }
        let result: [String: Any]
        if request == .identity {
            result = ["account": signedOut ? NSNull() : ["type": "chatgpt", "email": nullEmail ? NSNull() : "synthetic@example.test", "planType": "prolite"] as [String: Any]]
        } else {
            result = ["rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 35, "windowDurationMins": 10080], "secondary": NSNull()]]]
        }
        return AccountReadReply(data: try JSONSerialization.data(withJSONObject: ["id": wrongID ? -1 : id, "result": result]), identityRevision: revision)
    }
}

@MainActor
final class CurrentAccountReaderTests: XCTestCase {
    func testRequestsAreReadOnlyAndRefreshTokenIsFalse() throws {
        XCTAssertEqual(Set(AccountReadRequest.allCases.map(\.rawValue)), ["account/read", "account/rateLimits/read"])
        let encoded = try AccountReadRequest.identity.encoded(id: 1)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual((request["params"] as? [String: Bool])?["refreshToken"], false)
    }
    func testWeeklyReadChecksIdentityBeforeAndAfter() async throws {
        let transport = FakeAccountTransport()
        let reading = try await CurrentAccountReader(transport: transport).read()
        XCTAssertEqual(transport.calls, [.identity, .limits, .identity])
        XCTAssertEqual(reading.usage.limit?.primary?.remainingPercent, 65)
        XCTAssertNil(reading.usage.limit?.secondary)
        XCTAssertEqual(reading.usage.plan, "prolite")
        XCTAssertTrue(reading.usage.profileID.hasPrefix("current:"))
    }
    func testChangedAccountIsDiscarded() async throws {
        let transport = FakeAccountTransport(); transport.changeIdentity = true
        do { _ = try await CurrentAccountReader(transport: transport).read(); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? AccountReadError, .identityChanged) }
    }
    func testSignedOutSkipsUsageRequest() async throws {
        let transport = FakeAccountTransport(); transport.signedOut = true
        do { _ = try await CurrentAccountReader(transport: transport).read(); XCTFail("Expected sign-out state") }
        catch { XCTAssertEqual(error as? AccountReadError, .signedOut) }
        XCTAssertEqual(transport.calls, [.identity])
    }
    func testNullEmailIsSupportedWithoutInventedIdentity() async throws {
        let transport = FakeAccountTransport(); transport.nullEmail = true
        let reading = try await CurrentAccountReader(transport: transport).read()
        XCTAssertNil(reading.identity.email)
    }
    func testWrongResponseIDIsRejected() async throws {
        let transport = FakeAccountTransport(); transport.wrongID = true
        do { _ = try await CurrentAccountReader(transport: transport).read(); XCTFail("Expected mismatch") }
        catch { XCTAssertEqual(error as? AccountReadError, .malformed) }
    }
    func testFailureKeepsPreviousTimestampAndRedactsError() async {
        let transport = FakeAccountTransport()
        let reader = CurrentAccountReader(transport: transport)
        let state = CurrentUsageState()
        await state.refresh(using: reader)
        let before = state.reading?.usage.observedAt
        transport.fail = true
        await state.refresh(using: reader)
        XCTAssertNotNil(state.reading)
        XCTAssertEqual(state.reading?.usage.observedAt, before)
        XCTAssertEqual(state.error, .remote)
        XCTAssertFalse(state.error!.localizedDescription.contains("SECRET"))
        XCTAssertFalse(state.isLoading)
    }
    func testSignOutClearsOldAccountReading() async {
        let transport = FakeAccountTransport()
        let reader = CurrentAccountReader(transport: transport)
        let state = CurrentUsageState()
        await state.refresh(using: reader)
        transport.signedOut = true
        await state.refresh(using: reader)
        XCTAssertNil(state.reading)
    }
}
