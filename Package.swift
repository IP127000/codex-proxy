// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexProxyLauncher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CodexProxyLauncher",
            targets: ["CodexProxyLauncher"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexProxyLauncher",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
