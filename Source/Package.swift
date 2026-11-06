// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "States", platforms: [.macOS("26.0")],
    products: [.executable(name: "States", targets: ["States"])],
    targets: [
        .target(name: "CSMC", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "StatesCore", dependencies: ["CSMC"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "States", dependencies: ["StatesCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "StatesCoreTests", dependencies: ["StatesCore"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
