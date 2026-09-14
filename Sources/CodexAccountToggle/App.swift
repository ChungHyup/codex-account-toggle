import AppKit
import SwiftUI
import SwitchCore
import Combine

@main
struct SwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var item: NSStatusItem!
    let model = Model()
    let popover = NSPopover()
    var previewWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--render-preview") {
            guard model.isDemo else { NSApp.terminate(nil); return }
            let languageSuffix = L10n.language == .english ? "-en" : ""
            if CommandLine.arguments.contains("--confirmation-preview") {
                // Offscreen content preview of NSAlert. No process check, modal, or switch is invoked.
                NSApp.appearance = NSAppearance(named: .aqua)
                let running = !CommandLine.arguments.contains("--codex-closed")
                let alert = makeSwitchConfirmation(profileName: "Work", running: running)
                let view = NSHostingView(rootView: ConfirmationPreview(alert: alert, running: running))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: running ? 410 : 360), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        let name = "dist/confirmation-\(running ? "running" : "closed")\(languageSuffix).png"
                        try? png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name))
                    }
                }
                NSApp.terminate(nil)
                return
            }
            let dark = CommandLine.arguments.contains("--dark")
            let blocked = CommandLine.arguments.contains("--quit-blocked-preview")
            let state = blocked || CommandLine.arguments.contains("--error-preview")
            if state { model.notice = .error; model.message = L10n.text(blocked ? "Codex가 종료 요청을 거부했습니다. 작업을 끝낸 뒤 다시 시도하세요." : "전환 실패로 이전 로그인을 복구했습니다.") }
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let productPreview = CommandLine.arguments.contains("--product-preview")
            let expanded = !productPreview && CommandLine.arguments.contains("--settings-preview")
            let hosting = NSHostingView(rootView: Panel(model: model, expanded: expanded, productPreview: productPreview).background(Color(nsColor: .windowBackgroundColor)))
            // The panel sizes itself to its content; render exactly that.
            let size = hosting.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(blocked ? "dist/quit-blocked\(languageSuffix).png" : productPreview ? "dist/product-preview\(dark ? "-dark" : "")\(languageSuffix).png" : dark ? "dist/demo-preview-dark\(languageSuffix).png" : state ? "dist/demo-preview-error\(languageSuffix).png" : expanded ? "dist/demo-preview-settings\(languageSuffix).png" : "dist/demo-preview\(languageSuffix).png"))
                }
            }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--usage-check") {
            // Diagnostic: run the same live read the panel uses and print a token-free summary.
            guard !model.isDemo else { print("usage-check requires --live"); NSApp.terminate(nil); return }
            Task { @MainActor in
                model.refreshLiveUsage(force: true)
                for _ in 0..<60 where model.liveUsage.isLoading || model.usage[model.current ?? ""]?.source != .live && model.liveUsageError == nil {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                let current = model.current ?? "-"
                let snapshot = model.usage[current]
                print("current profile:", current.prefix(8), "| saved profiles:", model.profiles.count)
                print("live error:", model.liveUsageError ?? "none")
                print("source:", snapshot.map { "\($0.source)" } ?? "none", "| plan:", snapshot?.plan ?? "nil", "| label:", snapshot?.planLabel ?? "nil")
                for window in snapshot?.windows ?? [] {
                    print("window:", window.title, "| used:", window.usedPercent ?? -1, "| resets_at:", window.resetsAt ?? -1)
                }
                NSApp.terminate(nil)
            }
            return
        }
        // A previous-name instance may still be open; never terminate or run alongside it.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.chunghyup.codex-account-toggle")
        let legacyPeers = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codexswitch.menubar")
        if peers.count > 1 || !legacyPeers.isEmpty { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Codex Account Toggle")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        model.$usage.combineLatest(model.$current, model.$menuUsageEnabled)
            .receive(on: RunLoop.main).sink { [weak self] _, _, _ in self?.updateMenuTitle() }.store(in: &subscriptions)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateMenuTitle() }.store(in: &subscriptions)
        // Live mode: local session records for saved accounts plus an owner-authorized live read for the signed-in one.
        Timer.publish(every: 240, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.model.refreshUsage(); self?.model.refreshLiveUsage() }.store(in: &subscriptions)
        updateMenuTitle()
        popover.behavior = .transient
        popover.delegate = self
        let controller = NSHostingController(rootView: Panel(model: model))
        controller.sizingOptions = [.preferredContentSize] // popover height follows the compact content
        popover.contentViewController = controller
        if CommandLine.arguments.contains("--window") && model.isDemo {
            let hosting = NSHostingView(rootView: Panel(model: model))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("Codex Account Toggle · 데모")
            window.contentView = hosting
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            model.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // A menu-bar-only app does not receive clicks made in other apps, so a transient
            // popover can stay open; watch those clicks ourselves and close on the first one.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.popover.performClose(nil) }
            }
        }
    }
    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
    private func updateMenuTitle() {
        guard model.menuUsageEnabled else { item.button?.title = ""; return }
        let snapshot = model.current.flatMap { model.usage[$0] }
        let window = snapshot?.preferredWindow
        let remaining = window?.resetPassed(at: Date()) == true ? nil : window?.remainingPercent
        let value = remaining.map { "\(Int($0.rounded(.down)))%" } ?? "—"
        let stale = snapshot?.isStale(at: Date()) == true ? "~" : ""
        item.button?.title = " " + (model.isDemo ? "D " : "") + stale + value
        let prefix = snapshot?.source == .sessionLog ? L10n.text("기록 · ") : model.isDemo ? L10n.text("샘플 · ") : ""
        item.button?.toolTip = prefix + (window?.title ?? L10n.text("사용 한도")) + " · " + value + L10n.text(" 남음")
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var current: String?
    @Published var message = L10n.text("현재 로그인한 계정을 저장해 시작하세요.")
    @Published var notice: NoticeKind = .neutral
    @Published var busy = false
    @Published var recovery = false
    @Published var scenario: DemoScenario = .success
    @Published var usage: [String: UsageSnapshot] = [:]
    @Published var menuUsageEnabled = true
    @Published var liveUsageError: String?
    let liveUsage = CurrentUsageState()
    private var collectingUsage = false
    private var lastLiveRefresh: (id: String, at: Date)?
    let store: Store
    let isDemo: Bool
    let lifecycle: AppLifecycle
    let coordinator: SwitchCoordinator
    init() {
        isDemo = !CommandLine.arguments.contains("--live") || CommandLine.arguments.contains("--render-preview")
        if isDemo {
            do { store = try DemoWorkspace.make() }
            catch { fatalError(L10n.text("데모 작업 폴더를 만들 수 없습니다. 실제 계정에 접근하지 않고 종료합니다.")) }
            lifecycle = DemoLifecycle()
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            // Preserve the existing storage path; branding must not migrate credentials.
            store = Store(root: home.appendingPathComponent("Library/Application Support/CodexSwitch"), home: ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex"))
            lifecycle = CodexLifecycle()
        }
        coordinator = SwitchCoordinator(store: store, lifecycle: lifecycle)
        if isDemo { message = L10n.text("샘플 계정을 클릭해 보세요. 실제 Codex와 로그인에는 접근하지 않습니다.") }
        refresh()
        if isDemo {
            for (index, profile) in profiles.prefix(2).enumerated() {
                usage[profile.id] = try? UsageSnapshot.demo(profileID: profile.id, index: index)
            }
        }
    }
    func refresh() {
        do {
            profiles = try store.profiles()
            current = try? Identity(data: store.read(store.active)).key
            recovery = FileManager.default.fileExists(atPath: store.backup.path)
            if recovery { notice = .error; message = L10n.text("완료되지 않은 전환이 있습니다. 이전 로그인을 복구하세요.") }
        } catch { message = L10n.text("계정 목록을 읽지 못했습니다. 저장 폴더를 확인하세요.") }
        refreshUsage()
        refreshLiveUsage()
    }
    /// Owner-authorized (2026-09-14) live read for the signed-in account only. A short-lived
    /// `codex app-server` answers read-only account and rate-limit requests; this app never sees tokens.
    /// Saved inactive accounts are never queried, so credentials are never swapped for a reading.
    func refreshLiveUsage(force: Bool = false) {
        guard !isDemo, !busy, !recovery, !liveUsage.isLoading, let current, profiles.contains(where: { $0.id == current }) else { return }
        if !force, let last = lastLiveRefresh, last.id == current, Date().timeIntervalSince(last.at) < 60 { return }
        guard let executable = CodexExecutable.locate(candidates: codexCandidates()) else {
            liveUsageError = L10n.text("Codex 실행 파일을 찾지 못해 실시간 조회를 건너뜁니다.")
            return
        }
        lastLiveRefresh = (current, Date())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let transport = AppServerTransport(configuration: .init(executable: executable, codexHome: store.home, clientName: "codex-account-toggle", clientVersion: version))
        let reader = CurrentAccountReader(transport: transport)
        Task { @MainActor in
            defer { transport.close() }
            await liveUsage.refresh(using: reader)
            if let error = liveUsage.error { liveUsageError = error.localizedDescription; return }
            // Attribute only if the same account is still signed in after the read.
            guard let reading = liveUsage.reading,
                  let active = try? Identity(data: store.read(store.active)).key, active == current else { return }
            usage[current] = UsageSnapshot(profileID: current, plan: reading.usage.plan, limit: reading.usage.limit, observedAt: reading.usage.observedAt, source: .live)
            liveUsageError = nil
        }
    }
    private func codexCandidates() -> [URL] {
        var list: [URL] = []
        if let app = try? (lifecycle as? CodexLifecycle)?.codexURL() { list.append(app.appendingPathComponent("Contents/Resources/codex")) }
        return list + CodexExecutable.defaultCandidates
    }
    /// Live mode: quota comes from readings Codex already wrote to its local session logs.
    /// Nothing is launched or requested; the signed-in account is only noted for attribution.
    func refreshUsage() {
        guard !isDemo, !collectingUsage, !profiles.isEmpty else { return }
        if let current { try? store.note(identity: current, kind: .observed) }
        collectingUsage = true
        let root = store.root, home = store.home, ids = profiles.map(\.id)
        Task.detached(priority: .utility) {
            let result = SessionUsage.collect(store: Store(root: root, home: home), profileIDs: ids)
            await MainActor.run { [weak self] in
                guard let self else { return }
                var merged = result
                // A live reading for an account outranks an older local record for it.
                for (id, snapshot) in self.usage where snapshot.source == .live {
                    if let local = merged[id], local.observedAt > snapshot.observedAt { continue }
                    merged[id] = snapshot
                }
                self.usage = merged
                self.collectingUsage = false
            }
        }
    }
    func saveCurrent() {
        guard !isDemo else { return }
        do { try store.validateBackend(); try add(data: store.read(store.active), isSignedIn: true) }
        catch { show(error) }
    }
    func importAccount() {
        guard !isDemo else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("다른 계정의 auth.json 선택")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try add(data: store.read(url)) } catch { show(error) }
    }
    func add(data: Data, isSignedIn: Bool = false) throws {
        guard !isDemo else { return }
        let identity = try Identity(data: data)
        let alert = NSAlert()
        alert.messageText = L10n.text("계정 이름")
        alert.informativeText = L10n.text("메뉴에 표시할 이름을 입력하세요.")
        let field = NSTextField(string: identity.email)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("저장"))
        alert.addButton(withTitle: L10n.text("취소"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let profile = try store.save(data: data, name: field.stringValue)
        // A saved signed-in account anchors attribution of earlier session-log readings; an imported file does not.
        if isSignedIn { try? store.note(identity: profile.id, kind: .saved) }
        message = L10n.text("계정을 저장했습니다. 다른 계정으로 로그인한 뒤 다시 저장하면 목록에 추가됩니다.")
        refresh()
    }
    func switchTo(_ profile: Profile) {
        guard !busy, !recovery, profile.id != current else { return }
        if !isDemo {
            let running: Bool
            do { running = try lifecycle.isRunning() }
            catch { show(error); return }
            let alert = makeSwitchConfirmation(profileName: profile.name, running: running)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        notice = .neutral
        busy = true
        (lifecycle as? DemoLifecycle)?.scenario = scenario
        Task {
            defer { busy = false; refresh() }
            do {
                try await coordinator.switchTo(profile) { message = $0 }
                notice = .success
                message = isDemo ? L10n.text("데모 전환 완료. 가짜 계정만 변경했습니다.") : L10n.text("Codex를 다시 열었습니다. 앱에서 선택한 계정인지 확인하세요.")
            } catch { show(error) }
        }
    }
    func restore() {
        guard !busy else { return }
        do {
            guard try !lifecycle.isRunning() else { throw SwitchError(L10n.text("Codex와 CLI를 종료한 뒤 복구하세요.")) }
            try store.rollback()
            message = L10n.text("이전 로그인을 복구했습니다. Codex를 다시 여세요.")
            refresh()
        } catch { show(error) }
    }
    func show(_ error: Error) { notice = .error; message = (error as? SwitchError)?.errorDescription ?? L10n.text("파일 또는 앱 작업에 실패했습니다. 접근 권한과 설치 상태를 확인하세요.") }
    func rename(_ profile: Profile) {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("계정 이름 변경")
        let field = NSTextField(string: profile.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("저장"))
        alert.addButton(withTitle: L10n.text("취소"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.rename(profile, to: field.stringValue); refresh() }
        catch { show(error) }
    }
}

@MainActor
final class CodexLifecycle: AppLifecycle {
    func preflight() throws { _ = try codexURL() }
    func codexURL() throws -> URL {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { return url }
        throw SwitchError(L10n.text("Codex 앱을 찾지 못했습니다. Codex 앱을 설치하거나 한 번 실행하세요."))
    }
    func isRunning() throws -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").contains(where: { !$0.isTerminated }) { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // Inspect executable names only; never collect command arguments or tokens.
        process.arguments = ["-axo", "comm="]
        let pipe = Pipe(); process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SwitchError(L10n.text("Codex 프로세스 확인에 실패했습니다.")) }
        return String(decoding: bytes, as: UTF8.self).split(separator: "\n").contains {
            let path = String($0).trimmingCharacters(in: .whitespaces)
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            return name == "codex" || name.hasPrefix("codex-") || name.hasPrefix("codex (")
        }
    }
    func quit() async throws {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex") {
            guard app.terminate() else { throw SwitchError(L10n.text("Codex가 종료 요청을 거부했습니다. 작업을 끝낸 뒤 다시 시도하세요.")) }
        }
        for _ in 0..<60 {
            if try !isRunning() { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SwitchError(L10n.text("Codex 또는 CLI가 아직 실행 중입니다. 작업을 종료한 뒤 다시 시도하세요. 로그인은 변경하지 않았습니다."))
    }
    func launch() async throws {
        let url = try codexURL()
        let config = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

@MainActor
func makeSwitchConfirmation(profileName: String, running: Bool) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = running ? .warning : .informational
    alert.messageText = running
        ? L10n.text("계정 전환을 위해 Codex를 다시 열어야 합니다")
        : L10n.format("%@ 계정으로 전환할까요?", String(profileName))
    alert.informativeText = L10n.format("전환할 계정: %@", profileName) + "\n\n" + (running
        ? L10n.text("Codex 또는 CLI가 실행 중입니다. 진행 중인 작업을 마치고 CLI를 직접 종료하세요. 계속하면 Codex 앱을 정상 종료하고 계정을 전환한 뒤 다시 엽니다. 종료되지 않으면 전환을 중단합니다.")
        : L10n.text("계정을 전환한 뒤 Codex를 엽니다. 그 사이 Codex를 실행하면 종료 후 다시 열 수 있으니 새 작업을 시작하지 마세요."))
    // Return selects Cancel; restarting requires an explicit click.
    alert.addButton(withTitle: L10n.text("취소"))
    alert.addButton(withTitle: L10n.text(running ? "계정 전환 및 재시작" : "계정 전환 및 열기"))
    alert.buttons[0].keyEquivalent = "\r"
    alert.buttons[1].keyEquivalent = ""
    return alert
}

/// Visual content preview, not a pixel-exact capture of the system-owned modal.
private struct ConfirmationPreview: View {
    let alert: NSAlert
    let running: Bool
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: running ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 32)).foregroundStyle(running ? Color.orange : Color.accentColor)
            Text(alert.messageText).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
            Text(alert.informativeText).font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(alert.buttons[0].title).font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                Text(alert.buttons[1].title).font(.system(size: 13))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(24).frame(width: 360, height: running ? 410 : 360)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
