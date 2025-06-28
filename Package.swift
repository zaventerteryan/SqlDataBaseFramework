// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SqlDataBaseFramework",
    platforms: [
        .iOS(.v13), .macOS(.v11)
    ],
    products: [
        .library(
            name: "SqlDataBaseFramework",
            targets: ["SqlDataBaseFramework"]
        ),
    ],
    targets: [
        .target(
            name: "SqlDataBaseFramework",
            dependencies: []
        ),
        .testTarget(
            name: "SqlDataBaseFrameworkTests",
            dependencies: ["SqlDataBaseFramework"]
        ),
    ]
)