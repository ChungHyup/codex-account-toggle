import AppKit
import SwiftUI
import SwitchCore

/// The real Claude desktop app. Quits gracefully only; it never force-quits.
@MainActor
final class ClaudeDesktopLifecycle: AppLifecycle {
    static let bundleID = "com.anthropic.claudefordesktop"
    let dataFolder: URL
    init(dataFolder: URL) { self.dataFolder = dataFolder }

    func appURL() throws -> URL {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) { return url }
        throw SwitchError(L10n.text("Claude 데스크톱 앱을 찾지 못했습니다."))
    }
    func preflight() throws { _ = try appURL() }
    /// The app itself, its helpers, and Code binaries it runs from the data folder all keep the folder busy.
    func isRunning() throws -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).contains(where: { !$0.isTerminated }) { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="] // executable paths only, never arguments
        let pipe = Pipe(); process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SwitchError(L10n.text("Claude 프로세스 확인에 실패했습니다.")) }
        let all = ProcessScan.all(in: String(decoding: bytes, as: UTF8.self))
        let app = try appURL().path
        // Code binaries may run from the link path or from the folder it points to.
        let folders = Set([dataFolder.path, dataFolder.resolvingSymlinksInPath().path])
        return folders.contains { !ProcessScan.claudeDesktopBlockers(all, appPath: app, dataFolder: $0).isEmpty }
    }
    func quit() async throws {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID) {
            guard app.terminate() else { throw SwitchError(L10n.text("Claude가 종료 요청을 거부했습니다. 작업을 끝낸 뒤 다시 시도하세요.")) }
        }
        for _ in 0..<60 {
            if try !isRunning() { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SwitchError(L10n.text("Claude가 아직 실행 중입니다. 진행 중인 작업을 마친 뒤 다시 시도하세요. 계정은 바꾸지 않았습니다."))
    }
    func launch() async throws {
        _ = try await NSWorkspace.shared.openApplication(at: appURL(), configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Claude desktop accounts: saved folders behind the app's data folder link.
@MainActor
final class DesktopModel: ObservableObject {
    @Published var profiles: [DesktopProfile] = []
    @Published var activeID: String?
    @Published var state: DesktopFolderState = .missing
    @Published var signedIn = false
    @Published var installed = true
    @Published var busy = false
    @Published var notice: NoticeKind = .neutral
    @Published var message = ""
    let isDemo: Bool
    let store: DesktopProfileStore
    private let lifecycle: AppLifecycle
    private let coordinator: DesktopSwitchCoordinator

    init(isDemo: Bool) {
        self.isDemo = isDemo
        if isDemo {
            do { store = try DesktopDemoWorkspace.make() }
            catch { fatalError(L10n.text("데모 작업 폴더를 만들 수 없습니다. 실제 계정에 접근하지 않고 종료합니다.")) }
            lifecycle = DemoLifecycle()
        } else {
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            store = DesktopProfileStore(active: support.appendingPathComponent("Claude"),
                                        root: support.appendingPathComponent("CodexSwitch/claude-desktop"))
            lifecycle = ClaudeDesktopLifecycle(dataFolder: store.active)
        }
        coordinator = DesktopSwitchCoordinator(store: store, lifecycle: lifecycle)
        refresh()
    }

    var others: [DesktopProfile] { profiles.filter { $0.id != activeID } }
    var currentName: String? { activeID.flatMap { id in profiles.first { $0.id == id }?.name } }

    /// Read-only, except relinking the last account when the data folder path went missing while Claude is quit.
    func refresh() {
        installed = isDemo || NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktopLifecycle.bundleID) != nil
        if store.state() == .missing, (try? lifecycle.isRunning()) == false { _ = try? store.repairIfNeeded() }
        state = store.state()
        activeID = store.activeProfileID
        signedIn = store.liveAccountID != nil
        profiles = (try? store.profiles()) ?? []
    }

    func switchTo(_ profile: DesktopProfile) {
        guard !busy, profile.id != activeID else { return }
        if !isDemo {
            let alert = Self.confirmation(title: L10n.format("Claude를 ‘%@’ 계정으로 다시 엽니다", profile.name))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        guard let currentName = askCurrentNameIfNeeded() else { return }
        run { try await self.coordinator.switchTo(profile.id, currentName: currentName) { self.message = $0 } }
    }
    func addAccount() {
        guard !busy else { return }
        if !isDemo {
            let alert = Self.confirmation(title: L10n.text("Claude를 새 계정용으로 다시 엽니다"),
                                          detail: L10n.text("Claude가 로그인 화면으로 열립니다. 다른 계정으로 로그인하세요. 지금 계정은 그대로 보관되며 로그아웃되지 않습니다."))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        guard let name = Self.askName(title: L10n.text("새 Claude 계정 이름"), value: L10n.text("새 Claude 계정")),
              let currentName = askCurrentNameIfNeeded() else { return }
        run { try await self.coordinator.addAccount(name: name, currentName: currentName) { self.message = $0 } }
    }
    func rename(_ profile: DesktopProfile) {
        guard !busy, let name = Self.askName(title: L10n.text("계정 이름 변경"), value: profile.name) else { return }
        do { try store.rename(profile.id, to: name); refresh() } catch { show(error) }
    }
    func delete(_ profile: DesktopProfile) {
        guard !busy else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("‘%@’ 저장본을 삭제할까요?", profile.name)
        alert.informativeText = L10n.text("이 계정의 Claude 데이터 폴더를 휴지통으로 옮깁니다. 이 계정으로 다시 쓰려면 새로 로그인해야 합니다.")
        alert.addButton(withTitle: L10n.text("취소"))
        alert.addButton(withTitle: L10n.text("삭제"))
        alert.buttons[1].hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try store.remove(profile.id); refresh() } catch { show(error) }
    }

    /// The app's own folder is adopted on the first switch; it needs a name then.
    private func askCurrentNameIfNeeded() -> String? {
        guard state == .realDirectory else { return currentName ?? "Claude" }
        return Self.askName(title: L10n.text("지금 쓰는 Claude 계정 이름"), value: L10n.text("Claude 계정"),
                            detail: L10n.text("지금 로그인된 Claude 계정을 이 이름으로 보관합니다."))
    }
    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        notice = .neutral
        Task { @MainActor in
            defer { busy = false; refresh() }
            do { try await work(); notice = .neutral; message = "" } catch { show(error) }
        }
    }
    private func show(_ error: Error) {
        notice = .error
        message = (error as? SwitchError)?.errorDescription ?? L10n.text("파일 또는 앱 작업에 실패했습니다. 접근 권한과 설치 상태를 확인하세요.")
    }
    private static func confirmation(title: String, detail: String? = nil) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (detail.map { $0 + "\n\n" } ?? "")
            + L10n.text("Claude 데스크톱 앱을 종료합니다. 진행 중인 대화와 Code·Cowork 작업이 멈추니 응답이 끝난 뒤 진행하세요. Claude가 종료되지 않으면 아무것도 바꾸지 않습니다.")
        alert.addButton(withTitle: L10n.text("취소"))
        alert.addButton(withTitle: L10n.text("종료하고 진행"))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        return alert
    }
    private static func askName(title: String, value: String, detail: String? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail ?? L10n.text("메뉴에 표시할 이름을 입력하세요.")
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("저장"))
        alert.addButton(withTitle: L10n.text("취소"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

struct DesktopSection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var usage: ClaudeUsageBoard

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.text("Claude 데스크톱")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
            current
            Divider()
            if !model.installed {
                hint(L10n.text("Claude 데스크톱 앱이 설치되어 있지 않습니다."))
            } else if model.others.isEmpty {
                hint(L10n.text("계정 추가 → 다른 Claude 계정으로 로그인…으로 추가하세요. 로그아웃은 필요 없습니다."))
            } else {
                VStack(spacing: 0) { ForEach(model.others) { row($0) } }.padding(.vertical, 4)
            }
            if model.busy || model.notice == .error { notice }
        }
    }

    private var current: some View {
        HStack(spacing: 8) {
            badge(model.currentName ?? "C", size: 26, active: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.currentName ?? L10n.text("지금 쓰는 Claude 계정")).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(status).font(.system(size: 11.5)).foregroundStyle(statusIsWarning ? Palette.warning : .secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !usage.desktopCurrent.isEmpty { ClaudeUsageLines(entry: usage.desktopCurrent).padding(.top, 2) }
            }
            Spacer(minLength: 6)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Palette.accent)
                .opacity(model.activeID == nil ? 0 : 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.accent.opacity(0.06))
        .contextMenu {
            if let id = model.activeID, let profile = model.profiles.first(where: { $0.id == id }) {
                Button(L10n.text("이름 변경…")) { model.rename(profile) }
            }
            if let account = usage.desktopCurrent.account {
                Button(L10n.text("주간 초기화 시각 설정…")) { usage.editWeeklyReset(account: account) }
            }
        }
    }
    private var status: String {
        switch model.state {
        case .realDirectory: return L10n.text("아직 보관 전 · 처음 전환할 때 이 계정이 보관됩니다")
        case .linked: return model.signedIn ? L10n.text("Claude 데스크톱 · 사용 중") : L10n.text("로그인 대기 중 · Claude에서 로그인하세요")
        case .missing: return L10n.text("Claude 데스크톱을 한 번 실행해 로그인하세요")
        case .foreign: return L10n.text("데이터 폴더가 예상과 달라 전환을 멈춥니다")
        }
    }
    private var statusIsWarning: Bool { model.state == .foreign }

    private func row(_ profile: DesktopProfile) -> some View {
        Button { model.switchTo(profile) } label: {
            HStack(spacing: 8) {
                badge(profile.name, size: 22, active: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                    if let entry = usage.desktopSaved[profile.id], !entry.isEmpty { ClaudeUsageLines(entry: entry) }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle()).disabled(model.busy || model.state == .foreign)
        .help(L10n.format("%@ 계정으로 전환", profile.name))
        .contextMenu {
            Button(L10n.text("이름 변경…")) { model.rename(profile) }
            if let account = usage.desktopSaved[profile.id]?.account {
                Button(L10n.text("주간 초기화 시각 설정…")) { usage.editWeeklyReset(account: account) }
            }
            Divider()
            Button(L10n.text("계정 삭제…")) { model.delete(profile) }
        }
    }
    private func badge(_ name: String, size: CGFloat, active: Bool) -> some View {
        let color = active ? Palette.accent : Color.orange
        return Text(String(name.prefix(1))).font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var notice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if model.busy { ProgressView().controlSize(.mini) }
            else { Image(systemName: "exclamationmark.circle").font(.system(size: 11.5)) }
            Text(model.message).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !model.busy {
                Button { model.notice = .neutral } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16) }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("안내 닫기"))
            }
        }.foregroundStyle(model.notice == .error ? Palette.warning : Palette.accent)
            .padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            .background((model.notice == .error ? Palette.warning : Palette.accent).opacity(0.07))
    }
}

/// Terminal Claude Code accounts. Switching is instant and applies to `claude` commands started afterwards.
@MainActor
final class CLIModel: ObservableObject {
    @Published var profiles: [CLIProfile] = []
    @Published var activeID: String?
    @Published var emails: [String: String] = [:]
    @Published var defaultEmail: String?
    @Published var shimInstalled = false
    @Published var pathConfigured = false
    @Published var message = ""
    let isDemo: Bool
    let store: CLIProfileStore
    private let home: URL

    init(isDemo: Bool) {
        self.isDemo = isDemo
        if isDemo {
            do { store = try CLIDemoWorkspace.make() }
            catch { fatalError(L10n.text("데모 작업 폴더를 만들 수 없습니다. 실제 계정에 접근하지 않고 종료합니다.")) }
            home = store.defaultConfig.deletingLastPathComponent()
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
            store = CLIProfileStore(base: home.appendingPathComponent(".codex-account-toggle/claude-cli"), home: home)
        }
        refresh()
    }

    var ready: Bool { shimInstalled && pathConfigured }

    func refresh() {
        profiles = (try? store.profiles()) ?? []
        activeID = store.activeID
        defaultEmail = store.email(of: nil)
        emails = Dictionary(uniqueKeysWithValues: profiles.compactMap { p in store.email(of: p.id).map { (p.id, $0) } })
        shimInstalled = store.shimInstalled
        pathConfigured = isDemo || store.pathConfigured(home: home)
    }
    func select(_ id: String?) {
        do {
            try store.setActive(id)
            message = L10n.text("새로 여는 터미널의 claude부터 이 계정을 씁니다.")
        } catch { message = (error as? SwitchError)?.errorDescription ?? "" }
        refresh()
    }
    func add() {
        let alert = NSAlert()
        alert.messageText = L10n.text("새 터미널 Claude 계정 이름")
        alert.informativeText = L10n.text("새 계정 폴더를 만들고 선택합니다. 새 터미널에서 claude를 처음 실행하면 이 계정으로 한 번 로그인합니다.")
        let field = NSTextField(string: L10n.text("새 Claude 계정"))
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("저장"))
        alert.addButton(withTitle: L10n.text("취소"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let id = try store.create(name: field.stringValue)
            try store.setActive(id)
            if !ready { setUp() } else { message = L10n.text("새 터미널에서 claude를 실행해 로그인하세요.") }
        } catch { message = (error as? SwitchError)?.errorDescription ?? "" }
        refresh()
    }
    /// Installs the shim in this app's own folder and shows the PATH line; shell files are never edited.
    func setUp() {
        do { try store.installShim() } catch { message = L10n.text("CLI 전환 도구를 설치하지 못했습니다."); return }
        refresh()
        guard !pathConfigured else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("터미널 설정 한 줄이 필요합니다")
        alert.informativeText = L10n.text("아래 줄을 ~/.zshrc 끝에 추가하고 새 터미널을 여세요. 이 앱은 셸 설정 파일을 직접 고치지 않습니다.") + "\n\n" + store.pathLine
        alert.addButton(withTitle: L10n.text("복사"))
        alert.addButton(withTitle: L10n.text("닫기"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.pathLine, forType: .string)
        }
    }
    func rename(_ profile: CLIProfile) {
        let alert = NSAlert()
        alert.messageText = L10n.text("계정 이름 변경")
        let field = NSTextField(string: profile.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("저장"))
        alert.addButton(withTitle: L10n.text("취소"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.rename(profile.id, to: field.stringValue)
        refresh()
    }
    func delete(_ profile: CLIProfile) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("‘%@’ 저장본을 삭제할까요?", profile.name)
        alert.informativeText = L10n.text("이 계정의 설정 폴더를 휴지통으로 옮깁니다. 선택돼 있었다면 기본 계정(~/.claude)으로 돌아갑니다.")
        alert.addButton(withTitle: L10n.text("취소"))
        alert.addButton(withTitle: L10n.text("삭제"))
        alert.buttons[1].hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        try? store.remove(profile.id)
        refresh()
    }
}

struct CLISection: View {
    @ObservedObject var model: CLIModel
    @ObservedObject var usage: ClaudeUsageBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("터미널 Claude")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !model.ready {
                    Button(L10n.text("설정…"), action: model.setUp).buttonStyle(.link).font(.system(size: 11.5))
                }
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            row(id: nil, name: L10n.text("기본 계정"), email: model.defaultEmail, profile: nil)
            ForEach(model.profiles) { row(id: $0.id, name: $0.name, email: model.emails[$0.id], profile: $0) }
            if !model.ready {
                Text(L10n.text("설정 후 새로 여는 터미널의 claude에 적용됩니다."))
                    .font(.system(size: 11)).foregroundStyle(Palette.warning).padding(.horizontal, 12).padding(.bottom, 6)
            }
        }.padding(.bottom, 4)
    }

    private func row(id: String?, name: String, email: String?, profile: CLIProfile?) -> some View {
        let selected = model.activeID == id
        let entry = id.flatMap { usage.cliSaved[$0] } ?? (id == nil ? usage.cliDefault : ClaudeUsageBoard.Entry())
        return Button { model.select(id) } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12)).foregroundStyle(selected ? Palette.accent : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundStyle(.primary).lineLimit(1)
                    Text(email ?? L10n.text("로그인 전")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if !entry.isEmpty { ClaudeUsageLines(entry: entry) }
                }
                Spacer(minLength: 6)
            }.padding(.horizontal, 12).padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .help(L10n.text("새로 여는 터미널의 claude에 이 계정을 씁니다"))
        .contextMenu {
            if let account = entry.account {
                Button(L10n.text("주간 초기화 시각 설정…")) { usage.editWeeklyReset(account: account) }
            }
            if let profile {
                Button(L10n.text("이름 변경…")) { model.rename(profile) }
                Divider()
                Button(L10n.text("계정 삭제…")) { model.delete(profile) }
            }
        }
    }
}
