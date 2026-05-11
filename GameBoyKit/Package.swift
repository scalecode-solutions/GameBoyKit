// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameBoyKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "GameBoyKit",
            targets: ["GameBoyKit"]
        )
    ],
    targets: [
        .target(
            name: "GameBoyKit",
            path: "Sources/GameBoyKit"
        ),
        .testTarget(
            name: "GameBoyKitTests",
            dependencies: ["GameBoyKit"],
            path: "Tests/GameBoyKitTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
