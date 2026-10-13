import XCTest
@testable import SwitchCore

/// Fake home folders and a fake `claude` executable only.
final class CLIProfileTests: XCTestCase {
    var home: URL!
    var store: CLIProfileStore!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/skills"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        store = CLIProfileStore(base: home.appendingPathComponent(".codex-account-toggle/claude-cli"), home: home)
        store.discard = { try FileManager.default.removeItem(at: $0) }
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    /// Runs the installed shim with a fake real `claude` that prints its config folder and arguments.
    func runShim(_ args: [String], env: [String: String] = [:]) throws -> String {
        let fakeDir = home.appendingPathComponent("fake-bin")
        try FileManager.default.createDirectory(at: fakeDir, withIntermediateDirectories: true)
        let fake = fakeDir.appendingPathComponent("claude")
        try "#!/bin/sh\nprintf 'dir=%s\\n' \"${CLAUDE_CONFIG_DIR:-default}\"\nfor a in \"$@\"; do printf 'arg=%s\\n' \"$a\"; done\n"
            .write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let process = Process()
        process.executableURL = store.shim
        process.arguments = args
        let shimDir = store.shim.deletingLastPathComponent().path
        // The shim's own folder twice, then the real one: it must never call itself.
        process.environment = ["PATH": "\(shimDir):\(shimDir):\(fakeDir.path):/usr/bin:/bin"].merging(env) { $1 }
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testShimRunsTheSelectedAccount() throws {
        try store.installShim()
        XCTAssertTrue(store.shimInstalled)
        XCTAssertEqual(try runShim(["-p", "hi there"]), "dir=default\narg=-p\narg=hi there\n")
        let work = try store.create(name: "Work")
        try store.setActive(work)
        XCTAssertEqual(try runShim(["--version"]), "dir=\(try store.folder(for: work).path)\narg=--version\n")
        XCTAssertEqual(try runShim([], env: ["CLAUDE_CONFIG_DIR": "/explicit"]), "dir=/explicit\n", "an explicit choice wins")
        try store.setActive(nil)
        XCTAssertEqual(try runShim([]), "dir=default\n")
    }
    func testNewAccountLinksSharedCustomizations() throws {
        let id = try store.create(name: "Work")
        let dir = try store.folder(for: id)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: dir.appendingPathComponent("settings.json").path),
                       home.appendingPathComponent(".claude/settings.json").path)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: dir.appendingPathComponent("skills").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("CLAUDE.md").path), "missing items are not invented")
    }
    func testRemoveFallsBackToDefaultAndRenameIsDisplayOnly() throws {
        let id = try store.create(name: "Work")
        try store.setActive(id)
        try store.rename(id, to: "Company")
        XCTAssertEqual(store.activeID, id)
        try store.remove(id)
        XCTAssertNil(store.activeID)
        XCTAssertEqual(try store.profiles(), [])
        XCTAssertThrowsError(try store.setActive("missing-id"))
        XCTAssertThrowsError(try store.folder(for: "../x"))
    }
    func testEmailsComeFromEachConfigFolder() throws {
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["emailAddress": "me@example.test"]]).write(to: store.defaultState)
        let id = try store.create(name: "Work")
        XCTAssertEqual(store.email(of: nil), "me@example.test")
        XCTAssertNil(store.email(of: id), "not signed in yet")
        let demo = try CLIDemoWorkspace.make()
        XCTAssertEqual(demo.email(of: try demo.profiles()[0].id), "work@example.test")
        XCTAssertTrue(demo.shimInstalled)
        try? FileManager.default.removeItem(at: demo.defaultConfig.deletingLastPathComponent())
    }
    func testPathLineDetection() throws {
        XCTAssertFalse(store.pathConfigured(home: home))
        try (store.pathLine + "\n").write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        XCTAssertTrue(store.pathConfigured(home: home))
    }

    func testOutdatedShimIsUpgradedButForeignFileIsNot() throws {
        try store.installShim()
        let old = CLIProfileStore.shimScript.replacingOccurrences(of: "# Pinch Hitter:", with: "# Codex Account Toggle:")
        try Data(old.utf8).write(to: store.shim)
        XCTAssertFalse(store.shimInstalled)
        XCTAssertTrue(store.upgradeShimIfOutdated())
        XCTAssertTrue(store.shimInstalled)
        try Data("#!/bin/sh\nexec something-else\n".utf8).write(to: store.shim)
        XCTAssertFalse(store.upgradeShimIfOutdated())
        XCTAssertEqual(try String(contentsOf: store.shim, encoding: .utf8), "#!/bin/sh\nexec something-else\n")
    }
}
