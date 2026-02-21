// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceToText",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceToText",
            path: "Sources/VoiceToText",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
