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
final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let model = Model()
    let popover = NSPopover()
    var previewWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--render-preview") {
            guard model.isDemo else { NSApp.terminate(nil); return }
            let languageSuffix = L10n.language == .english ? "-en" : ""
            let dark = CommandLine.arguments.contains("--dark")
            let state = CommandLine.arguments.contains("--error-preview")
            if state { model.notice = .error; model.message = L10n.text("전환 실패로 이전 로그인을 복구했습니다.") }
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let expanded = CommandLine.arguments.contains("--settings-preview")
            let hosting = NSHostingView(rootView: Panel(model: model, expanded: expanded).background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height + (state ? 80 : 0) + (expanded ? 44 : 0)), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(dark ? "dist/demo-preview-dark\(languageSuffix).png" : state ? "dist/demo-preview-error\(languageSuffix).png" : expanded ? "dist/demo-preview-settings\(languageSuffix).png" : "dist/demo-preview\(languageSuffix).png"))
                }
            }
            NSApp.terminate(nil)
            return
        }
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.codexswitch.menubar")
        if peers.count > 1 { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Codex Switch")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        model.$usage.combineLatest(model.$current, model.$menuUsageEnabled)
            .receive(on: RunLoop.main).sink { [weak self] _, _, _ in self?.updateMenuTitle() }.store(in: &subscriptions)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateMenuTitle() }.store(in: &subscriptions)
        updateMenuTitle()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        popover.contentViewController = NSHostingController(rootView: Panel(model: model))
        if CommandLine.arguments.contains("--window") && model.isDemo {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: PanelLayout.height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("Codex Switch · 데모")
            window.contentViewController = NSHostingController(rootView: Panel(model: model))
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    private func updateMenuTitle() {
        guard model.menuUsageEnabled else { item.button?.title = ""; return }
        let snapshot = model.current.flatMap { model.usage[$0] }
        let window = snapshot?.preferredWindow
        let remaining = window?.resetPassed(at: Date()) == true ? nil : window?.remainingPercent
        let value = remaining.map { "\(Int($0.rounded(.down)))%" } ?? "—"
        let stale = snapshot?.isStale(at: Date()) == true ? "~" : ""
        item.button?.title = " " + (model.isDemo ? "D " : "") + stale + value
        item.button?.toolTip = (model.isDemo ? L10n.text("샘플 · ") : "") + (window?.title ?? L10n.text("사용 한도")) + " · " + value + L10n.text(" 남음")
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
    }
    func saveCurrent() {
        guard !isDemo else { return }
        do { try store.validateBackend(); try add(data: store.read(store.active)) }
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
    func add(data: Data) throws {
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
        try store.save(data: data, name: field.stringValue)
        message = L10n.text("계정을 저장했습니다. 다른 계정으로 로그인한 뒤 다시 저장하면 목록에 추가됩니다.")
        refresh()
    }
    func switchTo(_ profile: Profile) {
        guard !busy else { return }
        if !isDemo {
            let alert = NSAlert()
            alert.messageText = L10n.format("%@ 계정으로 전환할까요?", String(profile.name))
            alert.informativeText = L10n.text("모든 Codex 작업과 CLI를 마쳤는지 확인하세요. 계속하면 Codex를 정상 종료하고 로그인 교체 후 다시 엽니다.")
            alert.addButton(withTitle: L10n.text("작업 완료 · 전환"))
            alert.addButton(withTitle: L10n.text("취소"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
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
