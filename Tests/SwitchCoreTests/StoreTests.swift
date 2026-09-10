import XCTest
@testable import SwitchCore

final class StoreTests: XCTestCase {
    var base: URL!
    var store: Store!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = base.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = Store(root: base.appendingPathComponent("profiles"), home: home)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: base) }
    func fixture(_ account: String, refresh: String = "fake-refresh") -> Data {
        Data("{\"auth_mode\":\"chatgpt\",\"tokens\":{\"account_id\":\"\(account)\",\"access_token\":\"fake-access\",\"refresh_token\":\"\(refresh)\"}}".utf8)
    }
    func testSwitchRollbackPreservesOtherFilesAndPermissions() throws {
        let a = fixture("a"), b = fixture("b")
        try store.write(a, to: store.active)
        let session = store.home.appendingPathComponent("session.json")
        try Data("keep".utf8).write(to: session)
        try store.save(data: a, name: "A")
        try store.save(data: b, name: "B")
        try store.replace(with: b)
        XCTAssertEqual(try store.read(store.active), b)
        XCTAssertEqual(try store.read(store.backup), a)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.active.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try store.replace(with: a))
        try store.rollback()
        XCTAssertEqual(try store.read(store.active), a)
        XCTAssertEqual(try String(contentsOf: session), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backup.path))
    }
    func testRefreshTokenSyncAndCommit() throws {
        let profile = try store.save(data: fixture("a"), name: "A")
        let fresh = fixture("a", refresh: "new-refresh")
        try store.write(fresh, to: store.active)
        try store.replace(with: fixture("b"))
        XCTAssertEqual(try store.auth(profile), fresh)
        try store.commit()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backup.path))
    }
    func testInvalidTargetNeverChangesActive() throws {
        let original = fixture("a")
        try store.write(original, to: store.active)
        XCTAssertThrowsError(try store.replace(with: Data("{}".utf8)))
        XCTAssertEqual(try store.read(store.active), original)
    }
    func testKeyringModeIsRejected() throws {
        try store.write(fixture("a"), to: store.active)
        try Data("cli_auth_credentials_store = \"keyring\"".utf8).write(to: store.home.appendingPathComponent("config.toml"))
        XCTAssertThrowsError(try store.validateBackend())
    }
    func testSymlinkReadIsRejected() throws {
        try store.write(fixture("a"), to: store.active)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: store.active)
        XCTAssertThrowsError(try store.read(link))
    }
    func testDuplicateAccountUpdatesOneEntry() throws {
        try store.save(data: fixture("a"), name: "A")
        try store.save(data: fixture("a", refresh: "updated"), name: "Renamed")
        XCTAssertEqual(try store.profiles().count, 1)
        XCTAssertEqual(try store.profiles().first?.name, "Renamed")
    }
    func testRenameDoesNotChangeCredentials() throws {
        let data = fixture("a")
        let profile = try store.save(data: data, name: "A")
        try store.write(data, to: store.active)
        try store.rename(profile, to: "  개인  ")
        XCTAssertEqual(try store.profiles().first?.name, "개인")
        XCTAssertEqual(try store.auth(profile), data)
        XCTAssertEqual(try store.read(store.active), data)
        XCTAssertThrowsError(try store.rename(profile, to: "   "))
    }
}
