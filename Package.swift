// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CodexSwitch", platforms: [.macOS(.v13)], products: [.executable(name: "CodexSwitch", targets: ["CodexSwitch"])], targets: [.target(name: "SwitchCore", resources: [.process("Resources")]), .executableTarget(name: "CodexSwitch", dependencies: ["SwitchCore"]), .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"])])
