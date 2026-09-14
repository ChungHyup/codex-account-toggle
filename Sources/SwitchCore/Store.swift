import Foundation
import CryptoKit
import Darwin

public struct SwitchError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct Identity: Equatable {
    public let key: String
    public let email: String
    public init(data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["auth_mode"] as? String ?? "chatgpt") == "chatgpt",
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty else {
            throw SwitchError(L10n.text("지원하는 ChatGPT 로그인 파일이 아닙니다."))
        }
        let parts = (tokens["id_token"] as? String ?? "").split(separator: ".")
        var claims: [String: Any] = [:]
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let bytes = Data(base64Encoded: payload) { claims = (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]) ?? [:] }
        }
        email = claims["email"] as? String ?? L10n.text("ChatGPT 계정")
        // Include the user as well as the workspace to avoid merging organization members.
        // Preserve identity across display-language changes, including legacy fallback IDs.
        let stable = account + ":" + (claims["sub"] as? String ?? claims["email"] as? String ?? "ChatGPT 계정")
        key = SHA256.hash(data: Data(stable.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct Profile: Codable, Identifiable {
    public let id: String
    public var name: String
    public let email: String
}

public final class Store {
    public let root: URL
    public let home: URL
    public var active: URL { home.appendingPathComponent("auth.json") }
    public var backup: URL { root.appendingPathComponent("recovery.auth.json") }
    /// Codex's own session logs; read only, never written.
    public var sessions: URL { home.appendingPathComponent("sessions") }
    private var index: URL { root.appendingPathComponent("profiles.json") }
    private var points: URL { root.appendingPathComponent("identity-points.json") }
    private var usage: URL { root.appendingPathComponent("usage.json") }
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    public init(root: URL, home: URL) { self.root = root; self.home = home }
    public func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    public func validateBackend() throws {
        let config = home.appendingPathComponent("config.toml")
        if FileManager.default.fileExists(atPath: config.path) {
            let text = try String(contentsOf: config)
            let pattern = #"(?m)^\s*cli_auth_credentials_store\s*=\s*["']([^"']+)["']"#
            let regex = try NSRegularExpression(pattern: pattern)
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text), text[range] != "file" {
                throw SwitchError(L10n.text("현재 인증 저장 방식은 지원하지 않습니다. 파일 기반 로그인만 전환할 수 있습니다."))
            }
        }
        _ = try Identity(data: read(active))
    }
    public func profiles() throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([Profile].self, from: read(index))
    }
    public func rename(_ profile: Profile, to name: String) throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80 else { throw SwitchError(L10n.text("계정 이름은 1~80자로 입력하세요.")) }
        var list = try profiles()
        guard let position = list.firstIndex(where: { $0.id == profile.id }) else { throw SwitchError(L10n.text("저장된 계정을 찾을 수 없습니다.")) }
        list[position].name = cleaned
        try write(JSONEncoder().encode(list), to: index)
    }
    /// Removes this app's saved copy of an account and its cached usage. The real sign-in is untouched.
    public func remove(_ profile: Profile) throws {
        var list = try profiles()
        guard let position = list.firstIndex(where: { $0.id == profile.id }) else { throw SwitchError(L10n.text("저장된 계정을 찾을 수 없습니다.")) }
        list.remove(at: position)
        try write(JSONEncoder().encode(list), to: index)
        let snapshot = root.appendingPathComponent(profile.id + ".auth.json")
        if FileManager.default.fileExists(atPath: snapshot.path) { try FileManager.default.removeItem(at: snapshot) }
        var cache = try cachedUsage()
        if cache.removeValue(forKey: profile.id) != nil { try saveUsage(cache) }
    }
    public func read(_ url: URL) throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else { throw SwitchError(L10n.text("일반 파일만 사용할 수 있습니다.")) }
        return try Data(contentsOf: url)
    }
    public func auth(_ profile: Profile) throws -> Data {
        guard profile.id.count == 64, profile.id.allSatisfy({ $0.isHexDigit }) else { throw SwitchError(L10n.text("저장된 계정 식별자가 올바르지 않습니다.")) }
        let data = try read(root.appendingPathComponent(profile.id + ".auth.json"))
        guard try Identity(data: data).key == profile.id else { throw SwitchError(L10n.text("저장된 계정과 로그인 파일이 일치하지 않습니다.")) }
        return data
    }
    @discardableResult public func save(data: Data, name: String) throws -> Profile {
        try prepare()
        let identity = try Identity(data: data)
        let profile = Profile(id: identity.key, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? identity.email : name, email: identity.email)
        var list = try profiles()
        if let i = list.firstIndex(where: { $0.id == profile.id }) { list[i] = profile } else { list.append(profile) }
        try write(data, to: root.appendingPathComponent(profile.id + ".auth.json"))
        try write(JSONEncoder().encode(list), to: index)
        return profile
    }
    public func write(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".switch-" + UUID().uuidString)
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SwitchError(L10n.text("보안 임시 파일을 만들 수 없습니다.")) }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: temp) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw SwitchError(L10n.text("로그인 파일 저장에 실패했습니다.")) }
                offset += count
            }
        }
        guard fsync(fd) == 0, Darwin.rename(temp.path, url.path) == 0 else { throw SwitchError(L10n.text("로그인 파일 교체에 실패했습니다.")) }
    }
    public func replace(with data: Data) throws {
        try validateBackend()
        _ = try Identity(data: data)
        let old = try read(active)
        try prepare()
        guard !FileManager.default.fileExists(atPath: backup.path) else { throw SwitchError(L10n.text("이전 전환의 복구 파일이 있습니다. 먼저 이전 로그인 복구를 실행하세요.")) }
        let identity = try Identity(data: old)
        if let profile = try profiles().first(where: { $0.id == identity.key }) { try save(data: old, name: profile.name) }
        try write(old, to: backup)
        try write(data, to: active)
        guard try read(active) == data else { throw SwitchError(L10n.text("교체된 로그인 파일 검증에 실패했습니다.")) }
    }
    public func rollback() throws {
        let data = try read(backup)
        _ = try Identity(data: data)
        try write(data, to: active)
        try commit()
    }
    public func commit() throws { try FileManager.default.removeItem(at: backup) }

    /// Moments when this app knew which account was signed in; used to attribute session-log readings.
    public func identityPoints() throws -> [IdentityPoint] {
        guard FileManager.default.fileExists(atPath: points.path) else { return [] }
        return try Store.decoder.decode([IdentityPoint].self, from: read(points))
    }
    /// Passive confirmations of an unchanged account are kept to one per hour.
    public func note(identity: String, kind: IdentityPointKind, at date: Date = Date()) throws {
        var list = try identityPoints()
        if kind == .observed, let last = list.last, last.id == identity, date.timeIntervalSince(last.at) < 3600 { return }
        list.append(IdentityPoint(at: date, id: identity, kind: kind))
        if list.count > 2000 { list.removeFirst(list.count - 2000) }
        try prepare()
        try write(Store.encoder.encode(list), to: points)
    }
    /// Last session-log reading per profile; survives Codex log rotation.
    public func cachedUsage() throws -> [String: SessionUsageObservation] {
        guard FileManager.default.fileExists(atPath: usage.path) else { return [:] }
        return try Store.decoder.decode([String: SessionUsageObservation].self, from: read(usage))
    }
    public func saveUsage(_ cache: [String: SessionUsageObservation]) throws {
        try prepare()
        try write(Store.encoder.encode(cache), to: usage)
    }
}
