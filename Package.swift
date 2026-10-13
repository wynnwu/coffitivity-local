// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoffitivityLocal",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CoffitivityKit"),
        .executableTarget(
            name: "CoffitivityLocal",
            dependencies: ["CoffitivityKit"]
        ),
        .testTarget(
            name: "CoffitivityKitTests",
            dependencies: ["CoffitivityKit"]
        ),
    ]
)
