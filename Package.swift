// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fidget",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "fidget", targets: ["fidget"]),
        .executable(name: "FidgetApp", targets: ["FidgetApp"]),
        .library(name: "FidgetCore", targets: ["FidgetCore"]),
    ],
    targets: [
        .target(name: "FidgetCore"),
        .executableTarget(name: "fidget", dependencies: ["FidgetCore"]),
        .executableTarget(name: "FidgetApp", dependencies: ["FidgetCore"]),
        .testTarget(name: "FidgetCoreTests", dependencies: ["FidgetCore"]),
    ]
)
