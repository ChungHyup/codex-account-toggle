// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CodexAccountToggle", platforms: [.macOS(.v13)], products: [.executable(name: "CodexAccountToggle", targets: ["CodexAccountToggle"])], targets: [.target(name: "SwitchCore", resources: [.process("Resources")]), .executableTarget(name: "CodexAccountToggle", dependencies: ["SwitchCore"]), .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"])])
