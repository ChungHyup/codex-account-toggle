import Foundation

@MainActor
public protocol AppLifecycle {
    func preflight() throws
    func quit() async throws
    func isRunning() throws -> Bool
    func launch() async throws
}

/// App lifecycle is injected so integration tests never control a real application.
@MainActor
public final class SwitchCoordinator {
    public let store: Store
    private let lifecycle: AppLifecycle
    public private(set) var isSwitching = false
    public init(store: Store, lifecycle: AppLifecycle) {
        self.store = store
        self.lifecycle = lifecycle
    }
    public func switchTo(_ profile: Profile, progress: (String) -> Void = { _ in }) async throws {
        guard !isSwitching else { throw SwitchError(L10n.text("이미 계정 전환을 진행 중입니다.")) }
        isSwitching = true
        defer { isSwitching = false }
        // All validation must precede any request to quit the application.
        try lifecycle.preflight()
        try store.validateBackend()
        guard !FileManager.default.fileExists(atPath: store.backup.path) else {
            throw SwitchError(L10n.text("먼저 이전 로그인을 복구하세요."))
        }
        let target = try store.auth(profile)
        if try Identity(data: store.read(store.active)).key == profile.id { return }
        progress(L10n.text("앱이 정상 종료되기를 기다리는 중…"))
        try await lifecycle.quit()
        guard try !lifecycle.isRunning() else { throw SwitchError(L10n.text("앱이 아직 실행 중입니다. 로그인은 변경하지 않았습니다.")) }
        do {
            try store.replace(with: target)
            progress(L10n.text("로그인 교체 완료 · 앱 실행 중…"))
            try await lifecycle.launch()
            try store.commit()
        } catch {
            if FileManager.default.fileExists(atPath: store.backup.path) {
                guard try !lifecycle.isRunning() else {
                    throw SwitchError(L10n.text("전환을 완료하지 못했습니다. 앱을 종료한 뒤 이전 로그인 복구를 실행하세요."))
                }
                do { try store.rollback() }
                catch { throw SwitchError(L10n.text("자동 복구에 실패했습니다. 복구 파일은 보존되어 있습니다.")) }
                try? await lifecycle.launch()
                throw SwitchError(L10n.text("전환 실패로 이전 로그인을 복구했습니다."))
            }
            throw error
        }
    }
}

public enum DemoScenario: String, CaseIterable, Identifiable {
    case success, quitRefused, launchFailed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .success: return L10n.text("정상 전환")
        case .quitRefused: return L10n.text("종료 거부")
        case .launchFailed: return L10n.text("재실행 실패 · 복구")
        }
    }
}

@MainActor
public final class DemoLifecycle: AppLifecycle {
    public var scenario: DemoScenario = .success
    public private(set) var running = true
    public private(set) var quitCount = 0
    public private(set) var launchCount = 0
    private var failNextLaunch = false
    public init() {}
    public func preflight() throws {}
    public func quit() async throws {
        quitCount += 1
        if scenario == .quitRefused { throw SwitchError(L10n.text("데모: 종료 요청이 거부되어 전환을 취소했습니다.")) }
        running = false
        failNextLaunch = scenario == .launchFailed
    }
    public func isRunning() throws -> Bool { running }
    public func launch() async throws {
        launchCount += 1
        if failNextLaunch {
            failNextLaunch = false
            throw SwitchError(L10n.text("데모: 앱 재실행 실패"))
        }
        running = true
    }
}

public enum DemoWorkspace {
    /// Always creates a fresh directory. Never consults HOME or CODEX_HOME.
    public static func make(in directory: URL = FileManager.default.temporaryDirectory) throws -> Store {
        let base = directory.appendingPathComponent("CodexSwitch-Demo-" + UUID().uuidString)
        let home = base.appendingPathComponent("mock-codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let store = Store(root: base.appendingPathComponent("profiles"), home: home)
        let first = try credentials(user: "personal", email: "personal@example.test")
        try store.save(data: first, name: L10n.text("개인 계정"))
        try store.save(data: credentials(user: "work", email: "work@example.test"), name: L10n.text("업무 계정"))
        try store.save(data: credentials(user: "side", email: "side@example.test"), name: L10n.text("사이드 프로젝트"))
        try store.write(first, to: store.active)
        return store
    }
    private static func credentials(user: String, email: String) throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["sub": user, "email": email])
            .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": [
            "account_id": "demo-" + user, "access_token": "FAKE-NOT-A-CREDENTIAL",
            "refresh_token": "FAKE-NOT-A-CREDENTIAL", "id_token": "demo.\(payload).unsigned"
        ]])
    }
}
