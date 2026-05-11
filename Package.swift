// swift-tools-version: 6.0
//
// The canonical Package.swift for the GameBoyKit project. SPM
// consumers point their dependency URL at the repo root and pick
// whichever of the three libraries they need.
//
// Inside the repo each library also has its own Package.swift
// (under GameBoyKit/, ConsoleKit/, CartridgeKit/) so they can be
// developed in isolation with `swift build` from those subdirs.
// Those nested manifests are ignored by SPM when this root manifest
// is the one consumed as a dependency.

import PackageDescription

let package = Package(
    name: "GameBoyKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // The chassis: SwiftUI Game Boy mockup, input, palette, themes.
        .library(name: "GameBoyKit", targets: ["GameBoyKit"]),
        // The "OS": cartridge format, boot/shelf/menu state machine,
        // PixelCanvas, device menu.
        .library(name: "ConsoleKit", targets: ["ConsoleKit"]),
        // Built-in games (Snake, QuestKid).
        .library(name: "CartridgeKit", targets: ["CartridgeKit"])
    ],
    targets: [
        .target(
            name: "GameBoyKit",
            path: "GameBoyKit/Sources/GameBoyKit"
        ),
        .target(
            name: "ConsoleKit",
            dependencies: ["GameBoyKit"],
            path: "ConsoleKit/Sources/ConsoleKit"
        ),
        .target(
            name: "CartridgeKit",
            dependencies: ["GameBoyKit", "ConsoleKit"],
            path: "CartridgeKit/Sources/CartridgeKit"
        ),
        .testTarget(
            name: "GameBoyKitTests",
            dependencies: ["GameBoyKit"],
            path: "GameBoyKit/Tests/GameBoyKitTests"
        ),
        .testTarget(
            name: "ConsoleKitTests",
            dependencies: ["ConsoleKit"],
            path: "ConsoleKit/Tests/ConsoleKitTests"
        ),
        .testTarget(
            name: "CartridgeKitTests",
            dependencies: ["CartridgeKit"],
            path: "CartridgeKit/Tests/CartridgeKitTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
