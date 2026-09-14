import Foundation

public enum TemporaryLoginError: Error, Equatable {
    case launchFailed, failed, cancelled, timeout, noCredentials
}

/// Owner-authorized (2026-09-14): signs in to another account by running `codex login` inside a
/// throwaway CODEX_HOME, the way the reference project does, so the signed-in account is never
/// logged out and its tokens stay valid. Only the resulting auth.json is returned; the temporary
/// home is removed afterwards and the CLI's output is discarded.
@MainActor
public final class TemporaryHomeLogin {
    public let executable: URL
    public let deviceAuth: Bool
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    public var isRunning: Bool { process?.isRunning == true }

    public init(executable: URL, deviceAuth: Bool = false) {
        self.executable = executable
        self.deviceAuth = deviceAuth
    }

    public func run(timeout: TimeInterval = 300) async throws -> Data {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-account-toggle-login-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home); process = nil }
        // Force file storage inside the temporary home, independent of future CLI defaults.
        try "cli_auth_credentials_store = \"file\"\n".write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = executable
        process.arguments = deviceAuth ? ["login", "--device-auth"] : ["login"]
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin",
                               "CODEX_HOME": home.path, "LANG": "en_US.UTF-8"]
        process.currentDirectoryURL = home
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        self.process = process
        cancelled = false
        timedOut = false
        let deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
            guard !Task.isCancelled, let self, let running = self.process, running.isRunning else { return }
            self.timedOut = true
            running.terminate()
        }
        defer { deadline.cancel() }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: TemporaryLoginError.launchFailed)
            }
        }
        if cancelled { throw TemporaryLoginError.cancelled }
        if timedOut { throw TemporaryLoginError.timeout }
        guard status == 0 else { throw TemporaryLoginError.failed }
        let credentials = home.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: credentials), !data.isEmpty else { throw TemporaryLoginError.noCredentials }
        return data
    }

    public func cancel() {
        guard let process, process.isRunning else { return }
        cancelled = true
        process.terminate()
    }
}
