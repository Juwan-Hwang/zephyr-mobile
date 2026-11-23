// zAssertGlassSnapshot —— iOS 26 Liquid Glass 快照（J-4）。
//
// 与 ZSnapshot.swift 的区别只在出图：视图放进宿主 App（ZephyrGlassHost）的 UIWindowScene 上的真窗口，
// makeKeyAndVisible 上屏，等合成后用 drawHierarchy(afterScreenUpdates:) 截图——玻璃由系统合成，layer.render 拍不到。
// 变体、录制模式（ZEPHYR_SNAPSHOT_RECORD / SNAPSHOT_RECORD）、比对精度与 ZSnapshot.swift 共用。
//
// 参考图：GlassSnapshotTests/__Snapshots__/<测试文件名>/<测试名>.<名字>-<变体>.png，只由 CI ios26 任务（macos-26 / iPhone 17）录制与校验。
// 非 iOS 26 系统直接跳过（玻璃只在 iOS 26 渲染，旧系统那套由 ZephyrSnapshotTests 覆盖）。

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
import ZephyrDesign

@MainActor
func zAssertGlassSnapshots<V: View>(
    named base: String,
    variants: [ZSnapshotVariant],
    settle: TimeInterval = 1.0,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    make: @MainActor (ZSnapshotVariant) async throws -> V
) async throws {
    guard #available(iOS 26, *) else {
        throw XCTSkip("Liquid Glass 快照只在 iOS 26+ 模拟器上录制 / 校验")
    }
    for variant in variants {
        let view = try await make(variant)
        let name = "\(base)-\(variant.name)"
        guard let image = await ZGlassRenderer.render(view, variant: variant, settle: settle) else {
            XCTFail("快照 \(name)：宿主 App 没有 UIWindowScene（ZephyrGlassSnapshotTests 必须以 ZephyrGlassHost 为 TEST_HOST）", file: file, line: line)
            continue
        }
        guard ZGlassRenderer.hasContent(image) else {
            XCTFail("快照 \(name) 拍出空图（全图亮度几乎无变化，窗口可能没上屏）", file: file, line: line)
            continue
        }
        zGlassCompare(image, named: name, file: file, testName: testName, line: line)
    }
}

@MainActor
private func zGlassCompare(_ image: UIImage, named name: String, file: StaticString, testName: String, line: UInt) {
    let directory = ZGlassPaths.directory(for: file)
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
            let attachment = XCTAttachment(data: (try? Data(contentsOf: reference)) ?? Data(), uniformTypeIdentifier: "public.png")
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

enum ZGlassPaths {
    /// GlassSnapshotTests/__Snapshots__/<测试文件名>/。
    static func directory(for file: StaticString) -> URL {
        let fileURL = URL(fileURLWithPath: "\(file)", isDirectory: false)
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        var root = fileURL.deletingLastPathComponent()
        while root.lastPathComponent != "GlassSnapshotTests", root.pathComponents.count > 1 {
            root.deleteLastPathComponent()
        }
        if root.lastPathComponent != "GlassSnapshotTests" { root = fileURL.deletingLastPathComponent() }
        return root.appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: true)
    }
}

@MainActor
enum ZGlassRenderer {
    static func render<V: View>(_ view: V, variant: ZSnapshotVariant, settle: TimeInterval) async -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return nil }

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

        // 与 ZSnapshot 同一画布：393×852、安全区 59/34（在 iPhone 17 模拟器上补差值）。
        let size = ZSnapshotLayout.iPhone16
        let target = ZSnapshotLayout.iPhone16SafeArea
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = variant.interfaceStyle
        window.traitOverrides.preferredContentSizeCategory = variant.contentSizeCategory
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let own = UIEdgeInsets(top: host.view.safeAreaInsets.top - host.additionalSafeAreaInsets.top, left: 0,
                               bottom: host.view.safeAreaInsets.bottom - host.additionalSafeAreaInsets.bottom, right: 0)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: target.top - own.top, left: 0, bottom: target.bottom - own.bottom, right: 0)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // 等 `.task` / 引擎流落定，再多等几帧让系统把玻璃合成上屏。
        let steps = max(1, Int((settle / 0.05).rounded(.up)))
        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: 50_000_000)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat(for: host.traitCollection)
        format.scale = ZSnapshotConfig.scale
        format.opaque = true
        format.preferredRange = .standard
        let background = UIColor.systemBackground.resolvedColor(with: host.traitCollection)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// 防空图：抽样亮度，最大最小差 < 8/255 视为空图（#310 第二轮 drawHierarchy 142 张全空的失败形态）。
    static func hasContent(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = 64, h = 64
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let lo = pixels.min(), let hi = pixels.max() else { return false }
        return Int(hi) - Int(lo) >= 8
    }
}
