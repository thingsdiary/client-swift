// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "thingsdiary-client-swift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "ThingsDiaryClient", targets: ["ThingsDiaryClient"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/jedisct1/swift-sodium.git",
            exact: "0.11.0"
        ),
    ],
    targets: [
        .target(
            name: "ThingsDiaryClient",
            dependencies: [
                .product(name: "Clibsodium", package: "swift-sodium"),
            ]
        ),
        .testTarget(
            name: "ThingsDiaryClientTests",
            dependencies: ["ThingsDiaryClient"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

