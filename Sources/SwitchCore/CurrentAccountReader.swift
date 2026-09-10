import Foundation

public enum AccountReadRequest: String, CaseIterable {
    case identity = "account/read"
    case limits = "account/rateLimits/read"
    public func encoded(id: Int) throws -> Data {
        var request: [String: Any] = ["id": id, "method": rawValue]
        if self == .identity { request["params"] = ["refreshToken": false] }
        return try JSONSerialization.data(withJSONObject: request)
    }
}

public struct AccountReadReply {
    public let data: Data
    /// Adapter must change this value whenever connection or account/workspace identity changes.
    public let identityRevision: UUID
    public init(data: Data, identityRevision: UUID) { self.data = data; self.identityRevision = identityRevision }
}

/// A future host adapter must enforce the deadline, response-size limit, and no credential writes.
/// There is deliberately no production Process/URLSession/credential-file adapter here.
@MainActor
public protocol CurrentAccountTransport {
    func request(_ request: AccountReadRequest, id: Int, timeout: TimeInterval) async throws -> AccountReadReply
}

public enum AccountReadError: Error, LocalizedError, Equatable {
    case malformed, remote, signedOut, unsupported, identityChanged, unavailable
    public var errorDescription: String? {
        switch self {
        case .malformed: return L10n.text("조회 응답을 확인할 수 없습니다.")
        case .remote: return L10n.text("사용량 조회에 실패했습니다. 이전 확인 값은 유지됩니다.")
        case .signedOut: return L10n.text("로그인된 계정을 확인하지 못했습니다.")
        case .unsupported: return L10n.text("현재 인증 방식의 사용량 조회는 지원하지 않습니다.")
        case .identityChanged: return L10n.text("조회 중 계정이 달라져 결과를 표시하지 않았습니다.")
        case .unavailable: return L10n.text("안전한 실시간 조회 연결을 준비 중입니다.")
        }
    }
}

public struct CurrentAccountIdentity: Decodable, Equatable {
    public let type: String
    public let email: String?
    public let planType: String?
}

public struct CurrentAccountReading {
    public let identity: CurrentAccountIdentity
    public let usage: UsageSnapshot
    public let revision: UUID
}

@MainActor
public final class CurrentAccountReader {
    private let transport: CurrentAccountTransport
    private var nextID = 0
    public init(transport: CurrentAccountTransport) { self.transport = transport }
    public func read(now: Date = Date()) async throws -> CurrentAccountReading {
        let before = try await fetch(.identity)
        let account = try identity(from: before.payload)
        let limits = try await fetch(.limits)
        let after = try await fetch(.identity)
        guard before.revision == limits.revision, before.revision == after.revision,
              account == (try identity(from: after.payload)) else { throw AccountReadError.identityChanged }
        let usage: UsageSnapshot
        do {
            // Session-scoped key: never infer a saved-profile identity from email or quota values.
            usage = try UsageSnapshot.parse(limits.payload, profileID: "current:" + before.revision.uuidString,
                                            plan: account.planType, observedAt: now)
        } catch { throw AccountReadError.malformed }
        return CurrentAccountReading(identity: account, usage: usage, revision: before.revision)
    }
    private func fetch(_ request: AccountReadRequest) async throws -> (payload: Data, revision: UUID) {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        let reply: AccountReadReply
        do { reply = try await transport.request(request, id: id, timeout: 10) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AccountReadError.remote } // Never surface raw transport text or tokens.
        try Task.checkCancellation()
        guard reply.data.count <= 1_048_576 else { throw AccountReadError.malformed }
        struct Envelope: Decodable { let id: Int }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: reply.data), envelope.id == id,
              let object = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any] else {
            throw AccountReadError.malformed
        }
        if let error = object["error"], !(error is NSNull) { throw AccountReadError.remote }
        guard let result = object["result"] as? [String: Any] else { throw AccountReadError.malformed }
        return (try JSONSerialization.data(withJSONObject: result), reply.identityRevision)
    }
    private func identity(from data: Data) throws -> CurrentAccountIdentity {
        struct Payload: Decodable { let account: CurrentAccountIdentity? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw AccountReadError.malformed }
        guard let account = payload.account else { throw AccountReadError.signedOut }
        guard account.type == "chatgpt" else { throw AccountReadError.unsupported }
        return account
    }
}

/// In-memory state only. Refresh failures do not turn old values into fresh data.
@MainActor
public final class CurrentUsageState {
    public private(set) var reading: CurrentAccountReading?
    public private(set) var isLoading = false
    public private(set) var error: AccountReadError?
    public init() {}
    public func refresh(using reader: CurrentAccountReader) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do { reading = try await reader.read(); error = nil }
        catch is CancellationError { return }
        catch let failure as AccountReadError {
            if failure == .identityChanged || failure == .signedOut || failure == .unsupported { reading = nil }
            error = failure
        } catch { self.error = .remote }
    }
}
