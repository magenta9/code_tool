// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeTool", targets: ["CodeToolApp"]),
        .library(name: "CodeToolCore", targets: ["CodeToolCore"]),
        .library(name: "CodeToolFoundation", targets: ["CodeToolFoundation"]),
        .library(name: "CodeToolUI", targets: ["CodeToolUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3")
    ],
    targets: [
        .executableTarget(
            name: "CodeToolApp",
            dependencies: ["CodeToolCore", "CodeToolUI"],
            path: "Sources/CodeToolApp",
            resources: [.process("Resources")]
        ),
        .target(
            name: "CodeToolFoundation",
            path: "Sources/CodeToolFoundation"
        ),
        .target(
            name: "CodeToolUI",
            dependencies: ["CodeToolFoundation"],
            path: "Sources/CodeToolUI"
        ),
        .target(
            name: "CodeToolCore",
            dependencies: [
                "CodeToolFoundation",
                "CodeToolUI",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/CodeToolCore"
        ),
        .testTarget(
            name: "CodeToolTests",
            dependencies: ["CodeToolCore", "CodeToolFoundation", "CodeToolUI"],
            path: "Tests/CodeToolTests"
        )
    ]
)
