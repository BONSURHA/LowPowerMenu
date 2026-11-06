// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LowPowerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LowPowerCore", targets: ["LowPowerCore"]),
    ],
    targets: [
        .target(name: "LowPowerCore"),
        .testTarget(
            name: "LowPowerCoreTests",
            dependencies: ["LowPowerCore"]
        ),
    ]
)
