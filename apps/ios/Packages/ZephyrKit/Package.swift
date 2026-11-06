// swift-tools-version: 5.10
// ZephyrKit — Zephyr iOS 的全部可复用代码。
//
//  ZephyrKit       纯 Swift：ZephyrEngine 协议、领域模型、格式化。Linux 可编译（CI + 沙箱单测）。
//  ZephyrMock      纯 Swift：MockEngine，按原型 design/prototype/pages.js 的确定性算法生成数据。Linux 可编译。
//  ZephyrCore      CoreEngine：包装 UniFFI 生成的 zephyr_core（仅 Apple 平台）。
//  ZephyrDesign    SwiftUI：tokens + Z* 组件库（仅 Apple 平台）。
//  ZephyrFeatures  SwiftUI：全部页面与 AppModel（仅 Apple 平台）。
import PackageDescription

// Linux（CI / 沙箱）只有纯 Swift 目标：ZephyrKit、ZephyrMock 及其测试。SwiftUI 目标仅在 Apple 平台加入。
var products: [Product] = [
    .library(name: "ZephyrKit", targets: ["ZephyrKit"]),
    .library(name: "ZephyrMock", targets: ["ZephyrMock"]),
]
var targets: [Target] = [
    .target(name: "ZephyrKit"),
    .target(name: "ZephyrMock", dependencies: ["ZephyrKit"]),
    .testTarget(name: "ZephyrKitTests", dependencies: ["ZephyrKit"]),
    .testTarget(name: "ZephyrMockTests", dependencies: ["ZephyrMock"]),
]
#if !os(Linux)
products += [
    .library(name: "ZephyrDesign", targets: ["ZephyrDesign"]),
    .library(name: "ZephyrFeatures", targets: ["ZephyrFeatures"]),
]
targets += [
    .target(name: "ZephyrDesign", dependencies: ["ZephyrKit"], resources: [.process("Resources")]),
    .target(name: "ZephyrFeatures", dependencies: ["ZephyrKit", "ZephyrMock", "ZephyrDesign"]),
]
#endif

let package = Package(
    name: "ZephyrKit",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
