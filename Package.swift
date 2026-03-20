// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextFix",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "TextFixKit", targets: ["TextFixKit"]),
        .executable(name: "TextFix", targets: ["TextFix"]),
    ],
    targets: [
        .target(name: "TextFixKit"),
        .executableTarget(
            name: "TextFix",
            dependencies: ["TextFixKit"]
        ),
        .testTarget(
            name: "TextFixKitTests",
            dependencies: ["TextFixKit"]
        ),
    ]
)
