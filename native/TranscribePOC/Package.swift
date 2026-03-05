// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TranscribePOC",
    platforms: [
        .macOS(.v13) // ScreenCaptureKit requires macOS 12.3+, SFSpeechRecognizer macOS 10.15+
    ],
    targets: [
        .executableTarget(
            name: "TranscribePOC",
            path: ".",
            sources: ["main.swift"]
        )
    ]
)
