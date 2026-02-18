// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Scriptik",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Scriptik",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources/Scriptik",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns", "Resources/__pycache__"],
            resources: [
                .copy("Resources/transcribe.py"),
            ]
        ),
    ]
)
