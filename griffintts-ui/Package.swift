// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "griffintts-ui",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "griffintts-ui", targets: ["griffintts-ui"])
    ],
    targets: [
        .executableTarget(
            name: "griffintts-ui",
            dependencies: []
        ),
        .testTarget(
            name: "griffintts-uiTests",
            dependencies: ["griffintts-ui"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
