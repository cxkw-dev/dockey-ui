// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dockey",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dockey", targets: ["Dockey"]),
        .library(name: "DockeyCore", targets: ["DockeyCore"]),
    ],
    targets: [
        .target(name: "DockeyCore"),
        .executableTarget(name: "Dockey", dependencies: ["DockeyCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "DockeySmoke", dependencies: ["DockeyCore"]),
        .testTarget(name: "DockeyCoreTests", dependencies: ["DockeyCore"]),
        .testTarget(name: "DockeyTests", dependencies: ["Dockey"]),
    ]
)
