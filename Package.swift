// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "flo",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "FloApp", targets: ["FloApp"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .library(name: "Features", targets: ["Features"])
    ],
    targets: [
        .target(
            name: "AppCore"
        ),
        .target(
            name: "Infrastructure",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "Features",
            dependencies: ["AppCore", "Infrastructure"]
        ),
        .executableTarget(
            name: "FloApp",
            dependencies: ["AppCore", "Infrastructure", "Features"]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"]
        ),
        .testTarget(
            name: "InfrastructureTests",
            dependencies: ["Infrastructure", "AppCore"]
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: ["Features", "Infrastructure", "AppCore"]
        )
    ]
)
