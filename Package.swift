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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3")
    ],
    targets: [
        .executableTarget(
            name: "CodeToolApp",
            dependencies: ["CodeToolCore"],
            path: "Sources/CodeToolApp",
            resources: [.process("Resources")]
        ),
        .target(
            name: "CodeToolCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/CodeToolCore"
        ),
        .testTarget(
            name: "CodeToolTests",
            dependencies: ["CodeToolCore"],
            path: "Tests/CodeToolTests"
        )
    ]
)
