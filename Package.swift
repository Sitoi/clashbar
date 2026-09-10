// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClashBar",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "ClashBar", targets: ["ClashBar"]),
        .executable(name: "ClashBarProxyHelper", targets: ["ClashBarProxyHelper"]),
        .library(name: "MihomoKit", targets: ["MihomoKit"]),
    ],
    targets: [
        .target(
            name: "ProxyHelperShared",
            path: "Sources/ProxyHelperShared"),
        .target(
            name: "MihomoKit",
            path: "Sources/MihomoKit"),
        .executableTarget(
            name: "ClashBar",
            dependencies: [
                "ProxyHelperShared",
                "MihomoKit",
            ],
            path: "Sources/ClashBar",
            resources: [
                .process("Resources"),
            ]),
        .executableTarget(
            name: "ClashBarProxyHelper",
            dependencies: ["ProxyHelperShared"],
            path: "Sources/ProxyHelper/Daemon"),
    ])
