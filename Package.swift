// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "freeflow",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "FreeFlowCore",
            targets: ["FreeFlowCore"]
        ),
        .executable(
            name: "freeflow-linux",
            targets: ["FreeFlowLinuxApp"]
        ),
    ],
    targets: [
        .target(
            name: "FreeFlowCore",
            path: "Sources",
            sources: [
                "LLMAPITransport.swift",
                "ModelConfiguration.swift",
                "PostProcessingService.swift",
                "TranscriptionService.swift",
                "ShortcutCore/ShortcutMatcher.swift",
                "ShortcutCore/ShortcutModels.swift",
            ]
        ),
        .executableTarget(
            name: "FreeFlowLinuxApp",
            dependencies: ["FreeFlowCore"],
            path: "LinuxSources/FreeFlowLinuxApp"
        ),
        .testTarget(
            name: "FreeFlowCoreTests",
            dependencies: ["FreeFlowCore"],
            path: "Tests/FreeFlowCoreTests"
        ),
    ]
)
