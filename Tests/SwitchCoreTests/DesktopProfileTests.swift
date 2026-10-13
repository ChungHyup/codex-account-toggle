import XCTest
@testable import SwitchCore

/// Synthetic folders and a fake app only. The real Claude data folder is never touched.
@MainActor
final class DesktopProfileTests: XCTestCase {
    var store: DesktopProfileStore!
    var base: URL { store.active.deletingLastPathComponent() }
    let personal = DesktopDemoWorkspace.personal, work = DesktopDemoWorkspace.work
    override func setUp() async throws { store = try DesktopDemoWorkspace.make() }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: base) }
    func marker() -> String? { try? String(contentsOf: store.active.appendingPathComponent("marker.txt")) }
    var workID: String { try! store.profiles().first { store.accountID(ofProfile: $0.id) == work }!.id }

    func testFirstSwitchAdoptsTheAppFolderThenRepointsTheLink() async throws {
        XCTAssertEqual(store.state(), .realDirectory)
        let app = DemoLifecycle()
        try await DesktopSwitchCoordinator(store: store, lifecycle: app).switchTo(workID, currentName: "Personal")
        XCTAssertEqual(store.state(), .linked(workID))
        XCTAssertEqual(store.liveAccountID, work)
        XCTAssertEqual(marker(), "synthetic \(work)")
        let adopted = try XCTUnwrap(try store.profiles().first { $0.name == "Personal" })
        XCTAssertEqual(store.accountID(ofProfile: adopted.id), personal, "the app's own folder is kept, not copied or deleted")
        XCTAssertEqual(app.quitCount, 1)
        XCTAssertEqual(app.launchCount, 1)
        try await DesktopSwitchCoordinator(store: store, lifecycle: app).switchTo(adopted.id, currentName: "unused")
        XCTAssertEqual(store.state(), .linked(adopted.id))
        XCTAssertEqual(marker(), "synthetic \(personal)")
        XCTAssertEqual(try store.profiles().count, 2, "later switches never adopt again")
    }
    func testSameAccountAndMissingFolderNeverQuitTheApp() async throws {
        let app = DemoLifecycle()
        let coordinator = DesktopSwitchCoordinator(store: store, lifecycle: app)
        try await coordinator.switchTo(workID, currentName: "Personal")
        try await coordinator.switchTo(workID, currentName: "x")
        do { try await coordinator.switchTo("does-not-exist", currentName: "x"); XCTFail("Expected missing folder") } catch {}
        XCTAssertEqual(app.quitCount, 1)
    }
    func testRefusedQuitChangesNothing() async throws {
        let app = DemoLifecycle(); app.scenario = .quitRefused
        do { try await DesktopSwitchCoordinator(store: store, lifecycle: app).switchTo(workID, currentName: "Personal"); XCTFail("Expected refusal") } catch {}
        XCTAssertEqual(store.state(), .realDirectory)
        XCTAssertEqual(marker(), "synthetic \(personal)")
        XCTAssertEqual(try store.profiles().count, 1)
    }
    func testAddAccountLinksAnEmptyFolderForSignIn() async throws {
        let app = DemoLifecycle()
        let id = try await DesktopSwitchCoordinator(store: store, lifecycle: app).addAccount(name: "Third", currentName: "Personal")
        XCTAssertEqual(store.state(), .linked(id))
        XCTAssertNil(store.liveAccountID, "the desktop app signs in and writes its account id itself")
        XCTAssertEqual(try store.profiles().map(\.name).sorted(), ["Personal", "Third", L10n.text("회사 Claude")].sorted())
        XCTAssertEqual(app.launchCount, 1)
    }
    func testForeignLinkOrFileIsNeverTouched() async throws {
        try FileManager.default.removeItem(at: store.active)
        try FileManager.default.createSymbolicLink(at: store.active, withDestinationURL: base.appendingPathComponent("elsewhere"))
        XCTAssertEqual(store.state(), .foreign)
        let app = DemoLifecycle()
        do { try await DesktopSwitchCoordinator(store: store, lifecycle: app).switchTo(workID, currentName: "x"); XCTFail("Expected refusal") } catch {}
        XCTAssertEqual(app.quitCount, 0)
        XCTAssertThrowsError(try store.link(to: workID))
    }
    func testRepairRelinksTheLastAccountWhenThePathGoesMissing() async throws {
        try await DesktopSwitchCoordinator(store: store, lifecycle: DemoLifecycle()).switchTo(workID, currentName: "Personal")
        try FileManager.default.removeItem(at: store.active) // removes only the link
        XCTAssertEqual(store.state(), .missing)
        XCTAssertTrue(try store.repairIfNeeded())
        XCTAssertEqual(store.state(), .linked(workID))
        XCTAssertFalse(try store.repairIfNeeded())
    }
    func testRemoveOnlyInactiveAndRenameIsDisplayOnly() async throws {
        try await DesktopSwitchCoordinator(store: store, lifecycle: DemoLifecycle()).switchTo(workID, currentName: "Personal")
        XCTAssertThrowsError(try store.remove(workID))
        try store.rename(workID, to: "Company")
        XCTAssertEqual(store.state(), .linked(workID), "renaming never moves a folder")
        let personalID = try XCTUnwrap(try store.profiles().first { $0.name == "Personal" }).id
        try store.remove(personalID)
        XCTAssertFalse(store.hasFolder(personalID))
        XCTAssertEqual(try store.profiles().map(\.name), ["Company"])
        XCTAssertThrowsError(try store.folder(for: "../escape"))
    }
    func testDesktopBlockersIgnoreTheChromeBridge() {
        let ps = """
          10 /Applications/Claude.app/Contents/MacOS/Claude
          11 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)
          12 /Applications/Claude.app/Contents/Helpers/chrome-native-host
          13 /Users/me/Library/Application Support/Claude/claude-code/2.1.295/x/claude.app/Contents/MacOS/claude
          14 /Users/me/.local/bin/claude
          15 /Applications/Claude Code.app/Contents/MacOS/other
        """
        let blockers = ProcessScan.claudeDesktopBlockers(ProcessScan.all(in: ps), appPath: "/Applications/Claude.app",
                                                         dataFolder: "/Users/me/Library/Application Support/Claude")
        XCTAssertEqual(blockers.map(\.pid), [10, 11, 13])
    }
}
