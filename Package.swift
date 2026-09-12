// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FacturXMacApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FacturXMacApp", targets: ["FacturXMacApp"]),
        .library(name: "FacturXCore", targets: ["FacturXCore"]),
    ],
    targets: [
        .target(
            name: "FacturXCore",
            path: "Sources/FacturXCore"
        ),
        .executableTarget(
            name: "FacturXMacApp",
            dependencies: ["FacturXCore"],
            path: "Sources/FacturXMacApp"
        ),
        .testTarget(
            name: "FacturXCoreTests",
            dependencies: ["FacturXCore"],
            path: "Tests/FacturXCoreTests"
        ),
    ]
)
