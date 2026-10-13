import Foundation
import Darwin

// Design adapted from ajipurn/agent-profiles (MIT): the desktop app's data folder becomes a symlink to a
// per-account folder, and a switch only repoints that link atomically. Safety rules follow
// erorplex/claude-desktop-profiles-macos (MIT): never force-quit, never clobber a real folder, stop
// without changes when the app does not quit. See docs/claude-desktop.md.

/// A saved Claude desktop account. `id` names its folder and never changes, so renaming is display-only.
public struct DesktopProfile: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum DesktopFolderState: Equatable {
    /// No data folder yet; the desktop app creates one on launch.
    case missing
    /// The app's own folder, not yet under this app's management.
    case realDirectory
    /// A link to one of this app's profile folders.
    case linked(String)
    /// A link or file this app did not create. Never touched.
    case foreign
}

/// Claude desktop keeps its sign-in cookies, encrypted token cache and account id in one data folder
/// (`~/Library/Application Support/Claude`). Each saved account gets its own folder in this store; the
/// data folder path becomes a symlink to the active one. Switching repoints the link with rename(2), so
/// the path is never missing or half-written, and no folder is ever copied or deleted by a switch.
public final class DesktopProfileStore {
    /// The desktop app's data folder path.
    public let active: URL
    /// This app's storage: `profiles/<id>` folders, the name list and the last linked id.
    public let root: URL
    /// Where a deleted account's folder goes. The Trash by default, so a deletion can be undone.
    public var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    public init(active: URL, root: URL) {
        self.active = active
        self.root = root
    }

    public var profilesDir: URL { root.appendingPathComponent("profiles") }
    private var index: URL { root.appendingPathComponent("profiles.json") }
    private var lastLinked: URL { root.appendingPathComponent("last-linked") }

    /// Folder names are our own ids: plain characters only.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
    public func folder(for id: String) throws -> URL {
        guard Self.isValidID(id) else { throw SwitchError(L10n.text("저장된 Claude 계정 식별자가 올바르지 않습니다.")) }
        return profilesDir.appendingPathComponent(id)
    }
    public func hasFolder(_ id: String) -> Bool { (try? folder(for: id)).map(isRealDirectory) ?? false }

    // MARK: Inspection (read-only, safe while the desktop app runs)

    public func state() -> DesktopFolderState {
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: active.path) {
            let resolved = URL(fileURLWithPath: target, relativeTo: active.deletingLastPathComponent()).standardizedFileURL
            let id = resolved.lastPathComponent
            if resolved.deletingLastPathComponent().path == profilesDir.standardizedFileURL.path, Self.isValidID(id), isRealDirectory(resolved) {
                return .linked(id)
            }
            return .foreign
        }
        switch itemType(active) {
        case nil: return .missing
        case .typeDirectory?: return .realDirectory
        default: return .foreign
        }
    }
    public var activeProfileID: String? {
        if case .linked(let id) = state() { return id }
        return nil
    }
    /// The account signed in to a desktop data folder, from the app's own files.
    public func accountID(inFolder folder: URL) -> String? {
        func value(_ file: String, _ key: String) -> String? {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(file)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = object[key] as? String, !text.isEmpty, text.count <= 64 else { return nil }
            return text
        }
        return value("config.json", "lastKnownAccountUuid") ?? value("cowork-enabled-cli-ops.json", "ownerAccountId")
    }
    public var liveAccountID: String? { accountID(inFolder: active) }
    public func accountID(ofProfile id: String) -> String? { (try? folder(for: id)).flatMap(accountID(inFolder:)) }

    public func profiles() throws -> [DesktopProfile] {
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([DesktopProfile].self, from: Data(contentsOf: index))
    }
    public func rename(_ id: String, to name: String) throws {
        let cleaned = try Self.clean(name)
        var list = try profiles()
        guard let i = list.firstIndex(where: { $0.id == id }) else { throw SwitchError(L10n.text("저장된 계정을 찾을 수 없습니다.")) }
        list[i].name = cleaned
        try writeIndex(list)
    }
    /// Deletes an account that is not in use. Its folder goes to `discard`.
    public func remove(_ id: String) throws {
        let url = try folder(for: id)
        guard activeProfileID != id else {
            throw SwitchError(L10n.text("사용 중인 Claude 계정은 삭제할 수 없습니다. 다른 계정으로 전환한 뒤 삭제하세요."))
        }
        if isRealDirectory(url) { try discard(url) }
        try writeIndex(try profiles().filter { $0.id != id })
    }

    // MARK: Changes (only while the desktop app is fully quit)

    /// Brings the app's own folder under management: one same-volume rename into the store, then a link
    /// back at the original path. Returns the new profile id. Requires `.realDirectory`.
    @discardableResult
    public func adoptActive(name: String) throws -> String {
        guard state() == .realDirectory else { throw SwitchError(L10n.text("Claude 데이터 폴더 상태를 확인할 수 없어 멈췄습니다.")) }
        let cleaned = try Self.clean(name)
        let id = Self.newID()
        let destination = try folder(for: id)
        try prepare()
        try rename(active, to: destination)
        do { try link(to: id) } catch {
            // Put the folder back rather than leave the app without its data.
            _ = Darwin.rename(destination.path, active.path)
            throw error
        }
        try append(DesktopProfile(id: id, name: cleaned))
        return id
    }
    /// An empty folder for signing in to another account; the app fills it on launch.
    @discardableResult
    public func createEmptyProfile(name: String) throws -> String {
        let cleaned = try Self.clean(name)
        let id = Self.newID()
        try prepare()
        try FileManager.default.createDirectory(at: try folder(for: id), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try append(DesktopProfile(id: id, name: cleaned))
        return id
    }
    /// Repoints the data folder path at a profile. The new link is created beside the old one and
    /// renamed over it, so the path is never missing. Refuses to replace a real folder or a foreign link.
    public func link(to id: String) throws {
        let target = try folder(for: id)
        guard isRealDirectory(target) else { throw SwitchError(L10n.text("보관된 Claude 계정 폴더를 찾을 수 없습니다.")) }
        switch state() {
        case .missing, .linked: break
        case .realDirectory, .foreign: throw SwitchError(L10n.text("Claude 데이터 폴더가 예상과 달라 건드리지 않았습니다."))
        }
        let temp = active.deletingLastPathComponent().appendingPathComponent(".codex-account-toggle-link-\(getpid())")
        try? FileManager.default.removeItem(at: temp)
        try FileManager.default.createSymbolicLink(at: temp, withDestinationURL: target)
        guard Darwin.rename(temp.path, active.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw SwitchError(L10n.text("Claude 데이터 폴더를 전환하지 못했습니다."))
        }
        try? Data(id.utf8).write(to: lastLinked, options: .atomic)
    }
    /// If the data folder path went missing after this app managed it, relink the last account rather than
    /// let the desktop app start signed out. Returns true when it repaired something.
    @discardableResult
    public func repairIfNeeded() throws -> Bool {
        guard state() == .missing, let data = try? Data(contentsOf: lastLinked),
              let id = String(data: data, encoding: .utf8), hasFolder(id) else { return false }
        try link(to: id)
        return true
    }

    // MARK: Internals

    private static func newID() -> String { UUID().uuidString.lowercased() }
    private static func clean(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80 else { throw SwitchError(L10n.text("계정 이름은 1~80자로 입력하세요.")) }
        return cleaned
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func append(_ profile: DesktopProfile) throws { try writeIndex(try profiles() + [profile]) }
    private func writeIndex(_ list: [DesktopProfile]) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: index, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: index.path)
    }
    /// rename(2) only: fails instead of copying when source and destination are on different volumes.
    private func rename(_ source: URL, to destination: URL) throws {
        guard itemType(destination) == nil else { throw SwitchError(L10n.text("이동할 위치에 이미 폴더가 있어 전환을 멈췄습니다.")) }
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw SwitchError(errno == EXDEV ? L10n.text("Claude 데이터 폴더가 다른 디스크에 있어 전환할 수 없습니다.")
                                             : L10n.text("Claude 데이터 폴더를 옮기지 못했습니다."))
        }
    }
    /// lstat semantics: a link is never mistaken for the folder it points to.
    private func itemType(_ url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }
    private func isRealDirectory(_ url: URL) -> Bool { itemType(url) == .typeDirectory }
}

/// Quits Claude desktop, repoints its data folder, and reopens it. Every check runs before the app is asked
/// to quit; the folder changes only after the app and its helpers are gone. Never force-quits.
@MainActor
public final class DesktopSwitchCoordinator {
    public let store: DesktopProfileStore
    private let lifecycle: AppLifecycle
    public private(set) var isSwitching = false
    public init(store: DesktopProfileStore, lifecycle: AppLifecycle) {
        self.store = store
        self.lifecycle = lifecycle
    }

    /// Switches to a saved account. `currentName` names the app's own folder when it is adopted on the first switch.
    public func switchTo(_ id: String, currentName: String, progress: (String) -> Void = { _ in }) async throws {
        guard store.hasFolder(id) else { throw SwitchError(L10n.text("보관된 Claude 계정 폴더를 찾을 수 없습니다.")) }
        if store.activeProfileID == id { return }
        try await withQuit(currentName: currentName, progress: progress) { try self.store.link(to: id) }
    }
    /// Opens the desktop app on an empty folder to sign in to another account. Returns the new profile id.
    @discardableResult
    public func addAccount(name: String, currentName: String, progress: (String) -> Void = { _ in }) async throws -> String {
        var created = ""
        try await withQuit(currentName: currentName, progress: progress) {
            created = try self.store.createEmptyProfile(name: name)
            try self.store.link(to: created)
        }
        return created
    }

    private func withQuit(currentName: String, progress: (String) -> Void, change: () throws -> Void) async throws {
        guard !isSwitching else { throw SwitchError(L10n.text("이미 계정 전환을 진행 중입니다.")) }
        isSwitching = true
        defer { isSwitching = false }
        try lifecycle.preflight()
        if store.state() == .foreign { throw SwitchError(L10n.text("Claude 데이터 폴더가 예상과 달라 건드리지 않았습니다.")) }
        progress(L10n.text("Claude 앱이 정상 종료되기를 기다리는 중…"))
        try await lifecycle.quit()
        guard try !lifecycle.isRunning() else { throw SwitchError(L10n.text("Claude가 아직 실행 중입니다. 계정은 바꾸지 않았습니다.")) }
        do {
            if store.state() == .realDirectory { try store.adoptActive(name: currentName) }
            try change()
        } catch {
            try? await lifecycle.launch()
            throw error
        }
        progress(L10n.text("Claude 계정 교체 완료 · 앱 실행 중…"))
        do { try await lifecycle.launch() }
        catch { throw SwitchError(L10n.text("계정은 바꿨지만 Claude 앱을 열지 못했습니다. 직접 열어 주세요.")) }
    }
}

public enum DesktopDemoWorkspace {
    public static let personal = "11111111-1111-4111-8111-111111111111"
    public static let work = "22222222-2222-4222-8222-222222222222"
    /// Synthetic folders under the temporary directory only. Never touches the real Claude data folder.
    /// Starts unmanaged (a real folder signed in to `personal`) with `work` already saved.
    public static func make(in directory: URL = FileManager.default.temporaryDirectory) throws -> DesktopProfileStore {
        let base = directory.appendingPathComponent("CodexAccountToggle-DesktopDemo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = DesktopProfileStore(active: base.appendingPathComponent("Claude"), root: base.appendingPathComponent("store"))
        store.discard = { try FileManager.default.removeItem(at: $0) }
        try seed(store.active, account: personal)
        let workID = try store.createEmptyProfile(name: L10n.text("회사 Claude"))
        try seed(store.folder(for: workID), account: work)
        return store
    }
    public static func seed(_ folder: URL, account: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["lastKnownAccountUuid": account]).write(to: folder.appendingPathComponent("config.json"))
        try Data("synthetic \(account)".utf8).write(to: folder.appendingPathComponent("marker.txt"))
    }
}
