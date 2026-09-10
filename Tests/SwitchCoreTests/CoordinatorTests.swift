import XCTest
@testable import SwitchCore

@MainActor
final class CoordinatorTests: XCTestCase {
    func withDemo(_ body: (Store, DemoLifecycle, SwitchCoordinator) async throws -> Void) async throws {
        let store = try DemoWorkspace.make()
        defer { try? FileManager.default.removeItem(at: store.home.deletingLastPathComponent()) }
        let app = DemoLifecycle()
        try await body(store, app, SwitchCoordinator(store: store, lifecycle: app))
    }
    func testSuccessfulSwitchUsesOnlyDemoWorkspace() async throws {
        try await withDemo { store, app, coordinator in
            XCTAssertTrue(store.home.path.contains("CodexSwitch-Demo-"))
            XCTAssertEqual(try store.profiles().count, 3)
            let target = try store.profiles()[1]
            try await coordinator.switchTo(target)
            XCTAssertEqual(try Identity(data: store.read(store.active)).key, target.id)
            XCTAssertEqual(app.quitCount, 1)
            XCTAssertEqual(app.launchCount, 1)
            XCTAssertTrue(app.running)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.backup.path))
            XCTAssertFalse(coordinator.isSwitching)
        }
    }
    func testQuitRefusedDoesNotChangeAuthentication() async throws {
        try await withDemo { store, app, coordinator in
            app.scenario = .quitRefused
            let before = try store.read(store.active)
            do { try await coordinator.switchTo(store.profiles()[1]); XCTFail("Expected refusal") }
            catch {}
            XCTAssertEqual(try store.read(store.active), before)
            XCTAssertEqual(app.launchCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.backup.path))
            XCTAssertFalse(coordinator.isSwitching)
        }
    }
    func testLaunchFailureRestoresOriginalAndRelaunches() async throws {
        try await withDemo { store, app, coordinator in
            app.scenario = .launchFailed
            let before = try store.read(store.active)
            do { try await coordinator.switchTo(store.profiles()[1]); XCTFail("Expected launch failure") }
            catch { XCTAssertTrue(error.localizedDescription.contains("복구")) }
            XCTAssertEqual(try store.read(store.active), before)
            XCTAssertEqual(app.launchCount, 2)
            XCTAssertTrue(app.running)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.backup.path))
        }
    }
    func testPendingRecoveryBlocksBeforeQuit() async throws {
        try await withDemo { store, app, coordinator in
            let before = try store.read(store.active)
            try store.write(before, to: store.backup)
            do { try await coordinator.switchTo(store.profiles()[1]); XCTFail("Expected recovery block") }
            catch {}
            XCTAssertEqual(app.quitCount, 0)
            XCTAssertEqual(try store.read(store.backup), before)
            XCTAssertEqual(try store.read(store.active), before)
        }
    }
    func testSelectingCurrentAccountDoesNotQuit() async throws {
        try await withDemo { store, app, coordinator in
            try await coordinator.switchTo(store.profiles()[0])
            XCTAssertEqual(app.quitCount, 0)
            XCTAssertEqual(app.launchCount, 0)
        }
    }
    func testTamperedProfileBlocksBeforeQuit() async throws {
        try await withDemo { store, app, coordinator in
            let target = try store.profiles()[1]
            try store.write(store.read(store.active), to: store.root.appendingPathComponent(target.id + ".auth.json"))
            do { try await coordinator.switchTo(target); XCTFail("Expected identity mismatch") }
            catch {}
            XCTAssertEqual(app.quitCount, 0)
        }
    }
    func testSeparateDemoInstancesHaveSeparateFiles() throws {
        let first = try DemoWorkspace.make()
        let second = try DemoWorkspace.make()
        defer {
            try? FileManager.default.removeItem(at: first.home.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.home.deletingLastPathComponent())
        }
        XCTAssertNotEqual(first.home, second.home)
        XCTAssertNotEqual(first.root, second.root)
    }
}
