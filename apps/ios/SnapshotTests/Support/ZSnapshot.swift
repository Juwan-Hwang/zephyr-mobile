// zAssertSnapshot —— Zephyr 的快照断言（在 swift-snapshot-testing 之上）。
//
// 与库自带 assertSnapshot 的区别：
//  1. 参考图缺失时录制并 **不判失败**（首跑 CI / 新增用例不会红），图同时作为 XCTAttachment 进 xcresult；
//     参考图存在时正常断言（precision 0.99 / perceptual 0.98，容忍不同机器的抗锯齿差异）。
//  2. 自己托管渲染：UIHostingController 放进 393×852（iPhone 16）的 UIWindow，等 `.task` / 异步数据落定
//     （`settle`）后再用 layer.render 出图。库的 `.image(on:)` 不会等 `.task`，NodesView / RulesView 会拍成空页。
//  3. 参考图统一放 SnapshotTests/__Snapshots__/<测试文件名>/<测试名>.<名字>.png（与库默认命名规则一致）。
//
// 录制模式：环境变量 ZEPHYR_SNAPSHOT_RECORD（优先）或 SNAPSHOT_RECORD（scheme 的 test action 已设为 missing）
//   missing（默认）缺图录制、不失败；有图断言
//   all             全部重录、不失败（改了视觉之后用）
//   never           缺图直接失败（参考图入库后可在 CI 打开，防止漏录）

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
import ZephyrDesign

// MARK: - 变体

/// 一次渲染的外观组合：深浅 × 字号 × 强调色。
struct ZSnapshotVariant: Sendable, Hashable {
    var name: String
    var colorScheme: ColorScheme
    var dynamicType: DynamicTypeSize
    var accent: ZTokens.Accent

    var interfaceStyle: UIUserInterfaceStyle { colorScheme == .dark ? .dark : .light }
    var contentSizeCategory: UIContentSizeCategory { UIContentSizeCategory(dynamicType) }

    static let dark = ZSnapshotVariant(name: "dark", colorScheme: .dark, dynamicType: .large, accent: .blue)
    static let light = ZSnapshotVariant(name: "light", colorScheme: .light, dynamicType: .large, accent: .blue)
    static let darkAX5 = ZSnapshotVariant(name: "dark-ax5", colorScheme: .dark, dynamicType: .accessibility5, accent: .blue)

    /// 强调色抽样：深色 + 指定强调色（light: true 则为浅色）。
    static func accentSample(_ accent: ZTokens.Accent, light: Bool = false) -> ZSnapshotVariant {
        ZSnapshotVariant(name: "\(light ? "light" : "dark")-\(accent.rawValue)",
                         colorScheme: light ? .light : .dark, dynamicType: .large, accent: accent)
    }

    /// 每个用例的基础三件套：深色 / 浅色 / AX5。
    static let standard: [ZSnapshotVariant] = [.dark, .light, .darkAX5]

    /// 基础三件套 + 一个强调色抽样（各用例轮流抽不同的强调色，整套覆盖 4 种）。
    static func standardPlusAccent(_ accent: ZTokens.Accent, light lightAccent: Bool = false) -> [ZSnapshotVariant] {
        standard + [.accentSample(accent, light: lightAccent)]
    }
}

// MARK: - 布局

enum ZSnapshotLayout: Sendable {
    /// iPhone 16 全屏 393×852，安全区 59 / 34（灵动岛机型）。
    case device
    /// 固定尺寸，无安全区（小组件 170×170 / 364×170、锁屏小组件等）。
    case fixed(CGSize)
    /// 固定宽度、高度自适应内容（组件陈列）。
    case fitWidth(CGFloat)

    static let iPhone16 = CGSize(width: 393, height: 852)
    static let iPhone16SafeArea = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
}

enum ZSnapshotConfig {
    /// 出图倍率。固定 2x：与模拟器无关、参考图体积可控（3x 约大 2.25 倍）。
    static let scale: CGFloat = 2
    static let precision: Float = 0.99
    static let perceptualPrecision: Float = 0.98

    enum Record: String { case missing, all, never }

    static var record: Record {
        let env = ProcessInfo.processInfo.environment
        // ZEPHYR_SNAPSHOT_RECORD 优先：scheme 里固定了 SNAPSHOT_RECORD=missing，命令行用
        // TEST_RUNNER_ZEPHYR_SNAPSHOT_RECORD=all 覆盖时不依赖 scheme 与 TEST_RUNNER_ 变量的合并顺序。
        let raw = env["ZEPHYR_SNAPSHOT_RECORD"] ?? env["SNAPSHOT_RECORD"] ?? env["SNAPSHOT_TESTING_RECORD"]
        return raw.flatMap(Record.init(rawValue:)) ?? .missing
    }
}

// MARK: - 断言

/// 对每个变体分别构造视图（页面用例每个变体需要一个全新的引擎/模型）并断言。
/// 文件名：`<测试名>.<base>-<变体名>.png`。
@MainActor
func zAssertSnapshots<V: View>(
    named base: String,
    variants: [ZSnapshotVariant] = ZSnapshotVariant.standard,
    layout: ZSnapshotLayout = .device,
    settle: TimeInterval = 0.4,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    make: (ZSnapshotVariant) async throws -> V
) async rethrows {
    for variant in variants {
        let view = try await make(variant)
        await zAssertSnapshot(of: view, named: "\(base)-\(variant.name)", variant: variant, layout: layout,
                              settle: settle, file: file, testName: testName, line: line)
    }
}

/// 单张快照。
@MainActor
func zAssertSnapshot<V: View>(
    of view: V,
    named name: String,
    variant: ZSnapshotVariant = .dark,
    layout: ZSnapshotLayout = .device,
    settle: TimeInterval = 0.4,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) async {
    let image = await ZSnapshotRenderer.render(view, variant: variant, layout: layout, settle: settle)
    guard image.size.width > 0, image.size.height > 0 else {
        XCTFail("快照 \(name) 渲染出空图（尺寸为 0）", file: file, line: line)
        return
    }

    let directory = ZSnapshotPaths.directory(for: file)
    let reference = ZSnapshotPaths.referenceURL(directory: directory, testName: testName, name: name)
    let exists = FileManager.default.fileExists(atPath: reference.path)

    switch (ZSnapshotConfig.record, exists) {
    case (.all, _), (.missing, false):
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: reference, options: .atomic)
        } catch {
            XCTFail("快照 \(name) 录制失败：\(error.localizedDescription)", file: file, line: line)
            return
        }
        XCTContext.runActivity(named: "已录制快照 \(reference.lastPathComponent)") { activity in
            let attachment = XCTAttachment(image: image)
            attachment.name = reference.lastPathComponent
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    case (.never, false):
        XCTFail("缺少参考图 \(reference.path)（SNAPSHOT_RECORD=never）", file: file, line: line)
    case (_, true):
        let failure = verifySnapshot(
            of: image,
            as: .image(precision: ZSnapshotConfig.precision,
                       perceptualPrecision: ZSnapshotConfig.perceptualPrecision,
                       scale: ZSnapshotConfig.scale),
            named: name,
            record: false,
            snapshotDirectory: directory.path,
            file: file,
            testName: testName,
            line: line
        )
        if let failure { XCTFail(failure, file: file, line: line) }
    }
}

// MARK: - 路径

enum ZSnapshotPaths {
    /// SnapshotTests/__Snapshots__/<测试文件名>/。从测试文件路径往上找到 SnapshotTests 目录。
    static func directory(for file: StaticString) -> URL {
        let fileURL = URL(fileURLWithPath: "\(file)", isDirectory: false)
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        var root = fileURL.deletingLastPathComponent()
        while root.lastPathComponent != "SnapshotTests", root.pathComponents.count > 1 {
            root.deleteLastPathComponent()
        }
        if root.lastPathComponent != "SnapshotTests" { root = fileURL.deletingLastPathComponent() }
        return root.appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: true)
    }

    /// 与 swift-snapshot-testing 的命名规则一致：`sanitize(testName).sanitize(name).png`。
    static func referenceURL(directory: URL, testName: String, name: String) -> URL {
        directory.appendingPathComponent("\(sanitize(testName)).\(sanitize(name))").appendingPathExtension("png")
    }

    static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    }
}

// MARK: - 渲染

@MainActor
enum ZSnapshotRenderer {
    static func render<V: View>(_ view: V, variant: ZSnapshotVariant, layout: ZSnapshotLayout,
                                settle: TimeInterval) async -> UIImage {
        let root = view
            .zAccent(variant.accent)
            .dynamicTypeSize(variant.dynamicType)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.zStaticRendering, true)
            .transaction { $0.animation = nil }
            .zPageBackground()
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = variant.interfaceStyle
        host.traitOverrides.preferredContentSizeCategory = variant.contentSizeCategory
        host.view.backgroundColor = .clear

        let window = UIWindow(frame: CGRect(origin: .zero, size: ZSnapshotLayout.iPhone16))
        window.overrideUserInterfaceStyle = variant.interfaceStyle
        window.traitOverrides.preferredContentSizeCategory = variant.contentSizeCategory
        window.rootViewController = host
        window.isHidden = false

        // 快照期间关闭 UIKit 层动画（UICollectionView 更新、布局过渡），与 zStaticRendering 一起保证截图确定。
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        // 先按目标尺寸（fitWidth 先给足高度）布局一次，量出测试宿主 UIWindow 自带的安全区（模拟器为 59/34），
        // 再只补差值到目标安全区：device = iPhone 16 的 59/34，其余布局 = 0。避免重复计入使内容整体下移、小组件被裁切。
        let target: UIEdgeInsets
        var size: CGSize
        switch layout {
        case .device:
            size = ZSnapshotLayout.iPhone16
            target = ZSnapshotLayout.iPhone16SafeArea
        case .fixed(let s):
            size = s
            target = .zero
        case .fitWidth(let width):
            size = CGSize(width: width, height: 4000)
            target = .zero
        }
        window.frame = CGRect(origin: .zero, size: size)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let own = UIEdgeInsets(top: host.view.safeAreaInsets.top - host.additionalSafeAreaInsets.top,
                               left: 0,
                               bottom: host.view.safeAreaInsets.bottom - host.additionalSafeAreaInsets.bottom,
                               right: 0)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: target.top - own.top, left: 0, bottom: target.bottom - own.bottom, right: 0)
        host.view.layoutIfNeeded()
        if case .fitWidth(let width) = layout {
            let fitted = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            size = CGSize(width: width, height: max(1, ceil(fitted.height)))
        }
        window.frame = CGRect(origin: .zero, size: size)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // 等 `.task` / 引擎流 / UICollectionView 布局落定（冻结时钟下 MockEngine 不 sleep，几轮 runloop 足够）。
        let steps = max(1, Int((settle / 0.05).rounded(.up)))
        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: 50_000_000)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat(for: host.traitCollection)
        format.scale = ZSnapshotConfig.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            host.view.layer.render(in: ctx.cgContext)
        }

        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}
