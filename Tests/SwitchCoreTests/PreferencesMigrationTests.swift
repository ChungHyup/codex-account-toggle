import XCTest
@testable import SwitchCore

/// Pure value selection only; tests never read or write the app's real preferences.
final class PreferencesMigrationTests: XCTestCase {
    func testCopiesOnlyMissingValues() {
        let legacy: [String: Any] = ["liveMode": true, "panelTab": "claude", "appLanguage": "en", PreferencesMigration.doneKey: true]
        let copy = PreferencesMigration.values(from: legacy, existing: ["appLanguage"])
        XCTAssertEqual(Set(copy.keys), ["liveMode", "panelTab"])
        XCTAssertEqual(copy["liveMode"] as? Bool, true)
        XCTAssertTrue(PreferencesMigration.values(from: nil, existing: []).isEmpty)
    }
    func testDoesNothingUnderTheLegacyIdentifier() {
        XCTAssertEqual(PreferencesMigration.run(currentBundleID: PreferencesMigration.legacyBundleID), [])
        XCTAssertEqual(PreferencesMigration.run(currentBundleID: nil), [])
    }
}
