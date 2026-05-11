// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConsoleKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "ConsoleKit", targets: ["ConsoleKit"])
    ],
    dependencies: [
        .package(path: "../GameBoyKit")
    ],
    targets: [
        .target(
            name: "ConsoleKit",
            dependencies: [
                .product(name: "GameBoyKit", package: "GameBoyKit")
            ],
            path: "Sources/ConsoleKit"
        ),
        .testTarget(
            name: "ConsoleKitTests",
            dependencies: ["ConsoleKit"],
            path: "Tests/ConsoleKitTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
