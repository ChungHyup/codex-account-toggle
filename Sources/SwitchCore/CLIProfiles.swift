import Foundation

// Design adapted from ajipurn/agent-profiles (MIT): each terminal Claude Code account is its own
// CLAUDE_CONFIG_DIR, and a small `claude` shim earlier on PATH reads the selected account at every launch.
// Claude Code keys each config folder's login to its path, so folders are never renamed or moved.

public struct CLIProfile: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Terminal Claude Code accounts. Switching only rewrites a one-line file the shim reads, so it is instant
/// and affects `claude` commands started afterwards; running sessions keep their account.
public final class CLIProfileStore {
    /// This app's CLI folder (no spaces, so the PATH line stays simple).
    public let base: URL
    /// Claude Code's default config folder (`~/.claude`) and state file (`~/.claude.json`).
    public let defaultConfig: URL
    public let defaultState: URL
    public var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// Personal customizations linked into a new account so they follow every account.
    public static let sharedItems = ["settings.json", "CLAUDE.md", "skills", "commands", "agents"]

    public init(base: URL, home: URL) {
        self.base = base
        defaultConfig = home.appendingPathComponent(".claude")
        defaultState = home.appendingPathComponent(".claude.json")
    }

    public var profilesDir: URL { base.appendingPathComponent("profiles") }
    public var shim: URL { base.appendingPathComponent("bin/claude") }
    private var index: URL { base.appendingPathComponent("profiles.json") }
    private var activeFile: URL { base.appendingPathComponent("active") }
    /// The line the user adds to their shell profile so the shim runs before the real `claude`.
    public var pathLine: String { "export PATH=\"\(base.appendingPathComponent("bin").path):$PATH\"" }

    public func folder(for id: String) throws -> URL {
        guard DesktopProfileStore.isValidID(id) else { throw SwitchError(L10n.text("저장된 Claude 계정 식별자가 올바르지 않습니다.")) }
        return profilesDir.appendingPathComponent(id)
    }
    public func profiles() throws -> [CLIProfile] {
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([CLIProfile].self, from: Data(contentsOf: index))
    }
    /// Nil means the default `~/.claude` account.
    public var activeID: String? {
        guard let text = try? String(contentsOf: activeFile, encoding: .utf8) else { return nil }
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = try? folder(for: id), isDirectory(url) else { return nil }
        return id
    }
    public func setActive(_ id: String?) throws {
        guard let id else { try? FileManager.default.removeItem(at: activeFile); return }
        guard isDirectory(try folder(for: id)) else { throw SwitchError(L10n.text("저장된 계정을 찾을 수 없습니다.")) }
        try prepare()
        try Data((id + "\n").utf8).write(to: activeFile, options: .atomic)
    }
    /// A new config folder; the first `claude` run in it asks to sign in once.
    @discardableResult
    public func create(name: String) throws -> String {
        let cleaned = try Self.clean(name)
        let id = UUID().uuidString.lowercased()
        let dir = try folder(for: id)
        try prepare()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for item in Self.sharedItems {
            let source = defaultConfig.appendingPathComponent(item)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(item), withDestinationURL: source)
        }
        try writeIndex(try profiles() + [CLIProfile(id: id, name: cleaned)])
        return id
    }
    public func rename(_ id: String, to name: String) throws {
        let cleaned = try Self.clean(name)
        var list = try profiles()
        guard let i = list.firstIndex(where: { $0.id == id }) else { throw SwitchError(L10n.text("저장된 계정을 찾을 수 없습니다.")) }
        list[i].name = cleaned
        try writeIndex(list)
    }
    /// Removes an account's folder (to the Trash). If it was selected, `claude` falls back to the default account.
    public func remove(_ id: String) throws {
        let dir = try folder(for: id)
        if activeID == id { try setActive(nil) }
        if isDirectory(dir) { try discard(dir) }
        try writeIndex(try profiles().filter { $0.id != id })
    }
    /// The signed-in email Claude Code recorded for an account, for display only.
    public func email(of id: String?) -> String? { oauthAccount(of: id)?["emailAddress"] as? String }
    /// The account and organization ids Claude Code recorded, used to match desktop usage records.
    public func account(of id: String?) -> (account: String, org: String?)? {
        guard let account = oauthAccount(of: id), let uuid = account["accountUuid"] as? String, !uuid.isEmpty else { return nil }
        return (uuid, account["organizationUuid"] as? String)
    }
    /// The config folder Claude Code uses for an account (`~/.claude` for the default one).
    public func configFolder(of id: String?) -> URL? { id == nil ? defaultConfig : try? folder(for: id!) }
    /// Reads only the `oauthAccount` profile fields; Claude Code keeps no tokens in this file.
    private func oauthAccount(of id: String?) -> [String: Any]? {
        let state = id.flatMap { try? folder(for: $0).appendingPathComponent(".claude.json") } ?? defaultState
        guard let data = try? Data(contentsOf: state),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["oauthAccount"] as? [String: Any]
    }

    public var shimInstalled: Bool { (try? String(contentsOf: shim, encoding: .utf8)) == Self.shimScript }
    /// Rewrites a shim an earlier version of this app installed (same folder, older text), so an app update
    /// or rename never leaves the terminal setup looking broken. Files this app did not write are left alone.
    @discardableResult
    public func upgradeShimIfOutdated() -> Bool {
        guard let text = try? String(contentsOf: shim, encoding: .utf8), text != Self.shimScript,
              text.hasPrefix("#!/bin/sh\n"), text.contains("CLAUDE_CONFIG_DIR=\"$base/profiles/$id\"") else { return false }
        return (try? installShim()) != nil
    }
    public func installShim() throws {
        try FileManager.default.createDirectory(at: shim.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.shimScript.utf8).write(to: shim, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
    }
    /// Whether a shell startup file already puts the shim on PATH. Read-only.
    public func pathConfigured(home: URL) -> Bool {
        let marker = base.appendingPathComponent("bin").path
        return [".zshrc", ".zprofile", ".bash_profile", ".bashrc", ".profile"].contains { file in
            (try? String(contentsOf: home.appendingPathComponent(file), encoding: .utf8))?.contains(marker) == true
        }
    }

    /// POSIX sh. An explicit CLAUDE_CONFIG_DIR always wins; otherwise the selected account's folder is used.
    /// Then the first `claude` on PATH that is not this shim runs with the same arguments.
    public static let shimScript = """
    #!/bin/sh
    # Pinch Hitter: runs `claude` as the terminal account picked in the menu bar app.
    base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
    if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -f "$base/active" ]; then
      id=$(head -n 1 "$base/active" 2>/dev/null)
      case "$id" in
        ''|*[!A-Za-z0-9-]*) ;;
        *) if [ -d "$base/profiles/$id" ]; then CLAUDE_CONFIG_DIR="$base/profiles/$id"; export CLAUDE_CONFIG_DIR; fi ;;
      esac
    fi
    self="$base/bin/claude"
    IFS=:
    for dir in $PATH; do
      [ -n "$dir" ] || continue
      candidate="$dir/claude"
      if [ -x "$candidate" ] && [ ! -d "$candidate" ] && [ ! "$candidate" -ef "$self" ]; then
        unset IFS
        exec "$candidate" "$@"
      fi
    done
    echo "claude (Pinch Hitter): the real claude was not found on PATH" >&2
    exit 127

    """

    private static func clean(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80 else { throw SwitchError(L10n.text("계정 이름은 1~80자로 입력하세요.")) }
        return cleaned
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func writeIndex(_ list: [CLIProfile]) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: index, options: .atomic)
    }
    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

public enum CLIDemoWorkspace {
    /// A fake home with a default account and one saved account, under the temporary directory only.
    public static func make(in directory: URL = FileManager.default.temporaryDirectory) throws -> CLIProfileStore {
        let home = directory.appendingPathComponent("CodexAccountToggle-CLIDemo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["emailAddress": "personal@example.test", "accountUuid": DesktopDemoWorkspace.personal,
                                                                      "organizationUuid": DesktopDemoWorkspace.org]])
            .write(to: home.appendingPathComponent(".claude.json"))
        let store = CLIProfileStore(base: home.appendingPathComponent(".codex-account-toggle/claude-cli"), home: home)
        store.discard = { try FileManager.default.removeItem(at: $0) }
        let work = try store.create(name: L10n.text("회사 Claude"))
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["emailAddress": "work@example.test", "accountUuid": DesktopDemoWorkspace.work,
                                                                      "organizationUuid": DesktopDemoWorkspace.org]])
            .write(to: store.folder(for: work).appendingPathComponent(".claude.json"))
        // A synthetic usage-limit refusal, as Claude Code records it, lifting in 95 minutes.
        let projects = try store.folder(for: work).appendingPathComponent("projects/-demo")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let now = Date()
        let refusal: [String: Any] = ["type": "assistant", "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(-300)),
                                      "entrypoint": "cli", "quotaLimits": ["status": "rejected", "rateLimitType": "five_hour",
                                                                           "resetsAt": Int(now.timeIntervalSince1970 + 95 * 60)]]
        try JSONSerialization.data(withJSONObject: refusal).write(to: projects.appendingPathComponent("demo.jsonl"))
        try store.installShim()
        return store
    }
}
