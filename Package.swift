// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LangSwitcher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LangSwitcher", targets: ["LangSwitcher"])],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(name: "LangSwitcher", dependencies: ["SwitcherCore"]),
        .executableTarget(name: "SwitcherChecks", dependencies: ["SwitcherCore"], path: "Tests/SwitcherCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
