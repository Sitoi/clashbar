// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClashBar",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ClashBar", targets: ["ClashBar"]),
        .executable(name: "ClashBarProxyHelper", targets: ["ClashBarProxyHelper"]),
    ],
    targets: [
        .target(
            name: "ProxyHelperShared",
            path: "Sources/Helper/Shared"),
        .executableTarget(
            name: "ClashBar",
            dependencies: ["ProxyHelperShared"],
            path: "Sources/ClashBar",
            resources: [
                .copy("Resources/bin/mihomo"),
                .copy("Resources/Brand/clashbar-icon.png"),
                .copy("Resources/ConfigTemplates/ClashBar.yaml"),
                .process("Resources/Localization"),
            ]),
        .executableTarget(
            name: "ClashBarProxyHelper",
            dependencies: ["ProxyHelperShared"],
            path: "Sources/Helper/Daemon"),
    ])
