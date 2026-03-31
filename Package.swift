// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeTool", targets: ["CodeToolApp"]),
        .library(name: "CodeToolCore", targets: ["CodeToolCore"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CodeToolApp",
            dependencies: ["CodeToolCore"],
            path: "Sources/CodeToolApp"
        ),
        .target(
            name: "CodeToolCore",
            path: "Sources/CodeToolCore"
        ),
        .testTarget(
            name: "CodeToolTests",
            dependencies: ["CodeToolCore"],
            path: "Tests/CodeToolTests"
        )
    ]
)
