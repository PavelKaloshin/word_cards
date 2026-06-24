// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SerbianCards",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SerbianCards", targets: ["SerbianCards"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "SerbianCards",
            dependencies: [
                .product(name: "ZipArchive", package: "ZipArchive"),
            ],
            path: "SerbianCards"
        ),
        .testTarget(
            name: "SerbianCardsTests",
            dependencies: ["SerbianCards"],
            path: "SerbianCardsTests"
        ),
    ]
)
