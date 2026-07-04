// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LemmingsStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LemmingsStudio", targets: ["LemmingsStudio"])
    ],
    targets: [
        .executableTarget(
            name: "LemmingsStudio",
            path: "Sources/LemmingsStudio",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                // Audio render callbacks benefit from -Ounchecked in release,
                // but keep checked builds for development.
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .release))
            ]
        )
    ]
)
