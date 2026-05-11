// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CartridgeKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "CartridgeKit", targets: ["CartridgeKit"])
    ],
    dependencies: [
        .package(path: "../GameBoyKit"),
        .package(path: "../ConsoleKit")
    ],
    targets: [
        .target(
            name: "CartridgeKit",
            dependencies: [
                .product(name: "GameBoyKit", package: "GameBoyKit"),
                .product(name: "ConsoleKit", package: "ConsoleKit")
            ],
            path: "Sources/CartridgeKit"
        ),
        .testTarget(
            name: "CartridgeKitTests",
            dependencies: ["CartridgeKit"],
            path: "Tests/CartridgeKitTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
