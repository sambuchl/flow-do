// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowDoCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "FlowDoCore", targets: ["FlowDoCore"])],
    targets: [
        .target(name: "FlowDoCore", path: "FlowDo",
                exclude: ["App", "Input", "UI", "Networking"],
                sources: ["Core", "Persistence"]),
        .testTarget(name: "FlowDoCoreTests", dependencies: ["FlowDoCore"], path: "FlowDoTests")
    ])
