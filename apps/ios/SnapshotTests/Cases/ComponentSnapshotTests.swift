// Z* 关键组件陈列：ZConnectButton、ZLatencyPill、ZFlag、ZBadge。
// 宽 393、高度随内容（AX5 下自然变高）；每个组件一张图覆盖全部状态。

import SwiftUI
import XCTest
import ZephyrDesign

@MainActor
final class ComponentSnapshotTests: XCTestCase {

    private let width: CGFloat = 393

    /// 组件陈列行：左侧说明文字 + 右侧组件。
    private struct Row<Content: View>: View {
        var title: String
        @ViewBuilder var content: () -> Content

        var body: some View {
            HStack(spacing: ZTokens.Space.n4) {
                Text(verbatim: title)
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.textSecondary)
                Spacer(minLength: ZTokens.Space.n3)
                content()
            }
        }
    }

    private struct Gallery<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: ZTokens.Space.n4) { content() }
                .padding(ZTokens.Layout.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func testConnectButton() async {
        let gallery = Gallery {
            Row(title: "未连接") { ZConnectButton(phase: .off) {} }
            Row(title: "正在连接") { ZConnectButton(phase: .connecting) {} }
            Row(title: "已连接") { ZConnectButton(phase: .on) {} }
            Row(title: "正在断开") { ZConnectButton(phase: .disconnecting) {} }
            Row(title: "已连接 · 强调色") { ZConnectButton(phase: .on, tint: .accent) {} }
        }
        for variant in ZSnapshotVariant.standardPlusAccent(.pink) {
            await zAssertSnapshot(of: gallery, named: "connect-\(variant.name)", variant: variant, layout: .fitWidth(width))
        }
    }

    func testLatencyPill() async {
        let samples: [(String, Int?, Bool)] = [
            ("未检测", nil, false), ("检测中", nil, true), ("38 ms", 38, false),
            ("120 ms", 120, false), ("250 ms", 250, false), ("450 ms", 450, false), ("超时", -1, false),
        ]
        let gallery = Gallery {
            ForEach(samples.indices, id: \.self) { i in
                let s = samples[i]
                Row(title: s.0) {
                    ZLatencyPill(ms: s.1, isTesting: s.2, style: .text)
                    ZLatencyPill(ms: s.1, isTesting: s.2, style: .pill)
                }
            }
        }
        for variant in ZSnapshotVariant.standard {
            await zAssertSnapshot(of: gallery, named: "latency-\(variant.name)", variant: variant, layout: .fitWidth(width))
        }
    }

    func testFlag() async {
        let codes = ["SG", "HK", "JP", "TW", "US", "KR"]
        let gallery = Gallery {
            Row(title: "regular") { HStack { ForEach(codes, id: \.self) { ZFlag($0) } } }
            Row(title: "small") { HStack { ForEach(codes, id: \.self) { ZFlag($0, size: .small) } } }
            Row(title: "highlighted") { HStack { ZFlag("jp", isHighlighted: true); ZFlag("CHN") } }
        }
        for variant in ZSnapshotVariant.standardPlusAccent(.green) {
            await zAssertSnapshot(of: gallery, named: "flag-\(variant.name)", variant: variant, layout: .fitWidth(width))
        }
    }

    func testBadge() async {
        let tones: [(String, ZBadgeTone)] = [
            ("neutral", .neutral), ("accent", .accent), ("success", .success), ("warning", .warning), ("danger", .danger),
        ]
        let gallery = Gallery {
            ForEach(tones.indices, id: \.self) { i in
                let t = tones[i]
                Row(title: t.0) {
                    ZBadge(verbatim: "覆写", tone: t.1)
                    ZBadge(verbatim: "VMess", tone: t.1, filled: true)
                }
            }
        }
        for variant in ZSnapshotVariant.standardPlusAccent(.orange, light: true) {
            await zAssertSnapshot(of: gallery, named: "badge-\(variant.name)", variant: variant, layout: .fitWidth(width))
        }
    }
}
