import Foundation
import Darwin

/// Finds a Codex CLI binary without running anything.
public enum CodexExecutable {
    public static func locate(candidates: [URL], environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var urls: [URL] = []
        if let override = environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            urls.append(URL(fileURLWithPath: override))
        }
        urls.append(contentsOf: candidates)
        return urls.first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }
    public static var defaultCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".local/bin/codex"), URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex")]
    }
}

public enum AppServerTransportError: Error, Equatable {
    case launchFailed, handshakeFailed, homeMismatch, timeout, oversized, closed
}

/// Owner-authorized (2026-09-14) live adapter: starts a short-lived `codex app-server` over stdio,
/// performs the handshake, forwards only the reader's read-only requests, and stops the server.
/// Tokens stay inside Codex; this app never reads them. Codex may refresh the signed-in account's
/// credentials as it normally does. stderr is discarded so nothing raw can reach the UI.
@MainActor
public final class AppServerTransport: CurrentAccountTransport {
    public struct Configuration {
        public var executable: URL
        public var codexHome: URL
        public var clientName: String
        public var clientVersion: String
        /// The server is stopped this long after its last reply even if `close()` is never called.
        public var idleTimeout: TimeInterval
        public init(executable: URL, codexHome: URL, clientName: String, clientVersion: String, idleTimeout: TimeInterval = 5) {
            self.executable = executable
            self.codexHome = codexHome
            self.clientName = clientName
            self.clientVersion = clientVersion
            self.idleTimeout = idleTimeout
        }
    }
    public static let lineLimit = 1_048_576
    private static let identityChangeNotifications: Set<String> = ["account/updated", "account/login/completed"]

    private let configuration: Configuration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var idleTask: Task<Void, Never>?
    private var generation = 0
    /// Changes on every launch, shutdown, and account-change notification.
    public private(set) var revision = UUID()
    public var isRunning: Bool { process?.isRunning == true }

    public init(configuration: Configuration) {
        self.configuration = configuration
        signal(SIGPIPE, SIG_IGN) // a server that exits mid-write must surface as an error, not a crash
    }

    public func request(_ request: AccountReadRequest, id: Int, timeout: TimeInterval) async throws -> AccountReadReply {
        try await ensureRunning(timeout: timeout)
        let data = try await send(request.encoded(id: id), expecting: String(id), timeout: timeout)
        scheduleIdleClose()
        return AccountReadReply(data: data, identityRevision: revision)
    }

    /// Stops the server. Safe to call repeatedly.
    public func close() { shutdown(reason: .closed) }

    private func ensureRunning(timeout: TimeInterval) async throws {
        if let process, process.isRunning { return }
        shutdown(reason: .closed)
        let process = Process()
        process.executableURL = configuration.executable
        process.arguments = ["app-server", "--stdio"]
        process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin",
                               "CODEX_HOME": configuration.codexHome.path, "LANG": "en_US.UTF-8"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        generation += 1
        let launch = generation
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.serverExited(generation: launch) }
        }
        do { try process.run() } catch { throw AppServerTransportError.launchFailed }
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        buffer = Data()
        revision = UUID()
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor in self?.consume(data, generation: launch) }
        }
        let initID = "init-" + UUID().uuidString
        let params: [String: Any] = [
            "clientInfo": ["name": configuration.clientName, "title": configuration.clientName, "version": configuration.clientVersion],
            "capabilities": ["experimentalApi": false, "requestAttestation": false]
        ]
        let initialize = try JSONSerialization.data(withJSONObject: ["id": initID, "method": "initialize", "params": params])
        let reply = try await send(initialize, expecting: initID, timeout: timeout)
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            shutdown(reason: .handshakeFailed)
            throw AppServerTransportError.handshakeFailed
        }
        // The server must be reading the same credential home as this app.
        if let home = result["codexHome"] as? String,
           URL(fileURLWithPath: home).standardizedFileURL.path != configuration.codexHome.standardizedFileURL.path {
            shutdown(reason: .homeMismatch)
            throw AppServerTransportError.homeMismatch
        }
        try write(JSONSerialization.data(withJSONObject: ["method": "initialized"]))
    }

    private func send(_ data: Data, expecting key: String, timeout: TimeInterval) async throws -> Data {
        guard input != nil, pending[key] == nil else { throw AppServerTransportError.closed }
        return try await withCheckedThrowingContinuation { continuation in
            pending[key] = continuation
            do { try write(data) } catch {
                pending[key] = nil
                continuation.resume(throwing: AppServerTransportError.closed)
                shutdown(reason: .closed)
                return
            }
            deadlines[key] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                guard !Task.isCancelled, let self, let waiter = self.pending.removeValue(forKey: key) else { return }
                self.deadlines[key] = nil
                waiter.resume(throwing: AppServerTransportError.timeout)
                self.shutdown(reason: .timeout)
            }
        }
    }

    private func write(_ data: Data) throws {
        guard let input else { throw AppServerTransportError.closed }
        do { try input.write(contentsOf: data + Data([0x0A])) } catch { throw AppServerTransportError.closed }
    }

    private func consume(_ data: Data, generation launch: Int) {
        guard launch == generation else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard line.count <= Self.lineLimit else { shutdown(reason: .oversized); return }
            handle(line: Data(line))
        }
        if buffer.count > Self.lineLimit { shutdown(reason: .oversized) }
    }

    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let method = object["method"] as? String {
            // Server requests (approvals, attestation) are never answered; notifications only matter for identity.
            if object["id"] == nil, Self.identityChangeNotifications.contains(method) { revision = UUID() }
            return
        }
        let key: String
        switch object["id"] {
        case let number as NSNumber: key = number.stringValue
        case let text as String: key = text
        default: return
        }
        guard let waiter = pending.removeValue(forKey: key) else { return }
        deadlines.removeValue(forKey: key)?.cancel()
        waiter.resume(returning: line)
    }

    private func scheduleIdleClose() {
        idleTask?.cancel()
        let delay = configuration.idleTimeout
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.shutdown(reason: .closed)
        }
    }

    private func serverExited(generation launch: Int) {
        guard launch == generation else { return }
        shutdown(reason: .closed)
    }

    private func shutdown(reason: AppServerTransportError) {
        idleTask?.cancel()
        idleTask = nil
        for task in deadlines.values { task.cancel() }
        deadlines = [:]
        let waiters = pending
        pending = [:]
        for waiter in waiters.values { waiter.resume(throwing: reason) }
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        if let process, process.isRunning {
            // Closing stdin makes the server exit; SIGTERM is the fallback.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { process.terminate() } }
        }
        process = nil
        input = nil
        output = nil
        buffer = Data()
        revision = UUID()
        generation += 1
    }
}
