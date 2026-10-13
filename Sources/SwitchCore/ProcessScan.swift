import Foundation

/// Classifies Codex processes from `ps -axo pid=,comm=` output (executable paths only, never arguments).
public struct CodexProcess: Equatable {
    public let pid: Int32
    public let path: String
    public init(pid: Int32, path: String) { self.pid = pid; self.path = path }
}

public enum ProcessScan {
    /// Processes whose executable name is `codex`, `codex-*`, or `codex (…)`.
    public static func codexProcesses(in text: String) -> [CodexProcess] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { return nil }
            let path = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            guard name == "codex" || name.hasPrefix("codex-") || name.hasPrefix("codex (") else { return nil }
            return CodexProcess(pid: pid, path: path)
        }
    }
    /// Every process as pid and executable path.
    public static func all(in text: String) -> [CodexProcess] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { return nil }
            return CodexProcess(pid: pid, path: trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces))
        }
    }
    /// Processes that keep Claude desktop's data folder busy: the app and its helpers, and Claude Code
    /// binaries it runs from inside the data folder. The Chrome bridge helper is started by Chrome and
    /// does not use the data folder, so it never blocks a switch.
    public static func claudeDesktopBlockers(_ processes: [CodexProcess], appPath: String, dataFolder: String) -> [CodexProcess] {
        let app = appPath.hasSuffix("/") ? appPath : appPath + "/"
        let data = dataFolder.hasSuffix("/") ? dataFolder : dataFolder + "/"
        return processes.filter { process in
            if process.path.hasPrefix(app) { return !process.path.hasPrefix(app + "Contents/Helpers/chrome-native-host") }
            return process.path.hasPrefix(data)
        }
    }
    /// Leftovers of a quit desktop app: every remaining process lives inside its bundle.
    /// A CLI session outside the bundle means "not orphans", so the user's own work is never touched.
    public static func orphans(_ processes: [CodexProcess], insideBundle bundlePath: String) -> [CodexProcess]? {
        guard !processes.isEmpty else { return nil }
        let prefix = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
        return processes.allSatisfy { $0.path.hasPrefix(prefix) } ? processes : nil
    }
}
