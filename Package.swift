// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShotEditor",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ShotEditor",
            path: "Sources/ShotEditor"
        ),
        .testTarget(
            name: "ShotEditorTests",
            dependencies: ["ShotEditor"],
            path: "Tests/ShotEditorTests"
        )
    ]
)
