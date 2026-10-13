import Foundation

/// The app's preferences moved with the bundle identifier when it was renamed to Pinch Hitter.
/// Copies the earlier identifier's preferences once, never overwriting a value already set and never
/// deleting the old ones, so the old app keeps working if it is opened again.
public enum PreferencesMigration {
    public static let legacyBundleID = "com.chunghyup.codex-account-toggle"
    public static let doneKey = "migratedFromLegacyBundleID"

    /// The values to copy: everything in the old domain the new one does not already have.
    public static func values(from legacy: [String: Any]?, existing: Set<String>) -> [String: Any] {
        guard let legacy else { return [:] }
        return legacy.filter { !existing.contains($0.key) && $0.key != doneKey }
    }

    /// Runs once per Mac user. Returns the keys it copied.
    @discardableResult
    public static func run(defaults: UserDefaults = .standard, currentBundleID: String? = Bundle.main.bundleIdentifier) -> [String] {
        guard let currentBundleID, currentBundleID != legacyBundleID, !defaults.bool(forKey: doneKey) else { return [] }
        let existing = Set(defaults.persistentDomain(forName: currentBundleID)?.keys.map { $0 } ?? [])
        let copy = values(from: defaults.persistentDomain(forName: legacyBundleID), existing: existing)
        for (key, value) in copy { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: doneKey)
        return copy.keys.sorted()
    }
}
