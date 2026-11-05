// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZephyrCore",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "ZephyrCore", targets: ["ZephyrCore", "ZephyrCoreFFI"]),
        .library(name: "ZephyrApp", targets: ["ZephyrApp"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "PacketTunnel", targets: ["PacketTunnel"])
    ],
    targets: [
        .binaryTarget(
            name: "ZephyrCoreFFI",
            path: "ZephyrCore.xcframework"
        ),
        .target(
            name: "ZephyrCore",
            dependencies: ["ZephyrCoreFFI"],
            path: "Sources/UniFFI",
            sources: ["zephyr_core.swift"],
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "DesignSystem",
            dependencies: ["ZephyrCore"],
            path: "Sources/DesignSystem"
        ),
        .target(
            name: "ZephyrApp",
            dependencies: ["ZephyrCore", "DesignSystem", "PacketTunnel"],
            path: "Sources/ZephyrApp",
            sources: ["ZephyrApp.swift"]
        ),
        .target(
            name: "PacketTunnel",
            dependencies: ["ZephyrCore"],
            path: "Sources/PacketTunnel"
        )
    ]
)
