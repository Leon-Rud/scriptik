// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RecordToggle",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "RecordToggle",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/RecordToggle",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/transcribe.py"),
            ]
        ),
    ]
)
