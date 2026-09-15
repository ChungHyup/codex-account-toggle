import XCTest
@testable import SwitchCore

final class ProcessScanTests: XCTestCase {
    let sample = """
      101 /Applications/ChatGPT.app/Contents/Resources/codex
      102 /Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host
      103 /Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Versions/1/Helpers/Codex (Renderer).app/Contents/MacOS/Codex (Renderer)
      104 /usr/bin/login
      105 /Users/me/projects/codex-account-toggle/dist/Codex Account Toggle.app/Contents/MacOS/CodexAccountToggle
    """
    func testFindsOnlyCodexExecutables() {
        let found = ProcessScan.codexProcesses(in: sample)
        XCTAssertEqual(found.map(\.pid), [101, 102, 103])
    }
    func testOrphansRequireEveryProcessInsideTheBundle() {
        let inside = ProcessScan.codexProcesses(in: sample)
        XCTAssertEqual(ProcessScan.orphans(inside, insideBundle: "/Applications/ChatGPT.app")?.map(\.pid), [101, 102, 103])
        let withCLI = inside + [CodexProcess(pid: 200, path: "/Users/me/.local/bin/codex")]
        XCTAssertNil(ProcessScan.orphans(withCLI, insideBundle: "/Applications/ChatGPT.app"))
        XCTAssertNil(ProcessScan.orphans([], insideBundle: "/Applications/ChatGPT.app"))
        XCTAssertNil(ProcessScan.orphans(inside, insideBundle: "/Applications/ChatGPT.application"))
    }
}
