// QRScanSheet — 全屏扫码：取景框 + 说明；处理权限未决 / 拒绝 / 无摄像头。
// mode = .desktop 时文案改为“扫描电脑上 Zephyr 显示的二维码”。

import SwiftUI
import UIKit
import ZephyrDesign

struct QRScanSheet: View {
    var desktop: Bool
    var onCode: (String) -> Void
    @State private var scanner = QRCodeScanner()
    @State private var permission = QRCodeScanner.permission
    @State private var available = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if permission == .granted && available {
                    QRScannerView(scanner: scanner).ignoresSafeArea()
                    viewfinder
                } else {
                    blocked
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(desktop ? "在电脑上的 Zephyr 打开“设置 › 同步到手机”，扫描显示的二维码。" : "将订阅二维码放入框内，即可自动识别。")
                    .zType(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(ZTokens.Space.n6)
            }
            .navigationTitle(desktop ? "从电脑导入" : "扫描二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .task { await prepare() }
        .onDisappear { scanner.stop() }
    }

    private var viewfinder: some View {
        RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous)
            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
            .frame(width: 240, height: 240)
            .accessibilityHidden(true)
    }

    private var blocked: some View {
        VStack(spacing: ZTokens.Space.n4) {
            Image(systemName: available ? "camera.fill" : "camera.metering.unknown")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.6))
            Text(available ? "需要相机权限才能扫码" : "此设备没有可用的相机")
                .zType(.headline)
                .foregroundStyle(.white)
            if available && permission == .denied {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(ZTokens.Space.n6)
    }

    private func prepare() async {
        if permission == .undetermined { permission = await QRCodeScanner.requestPermission() }
        guard permission == .granted else { return }
        available = await scanner.configure()
        guard available else { return }
        scanner.onCode = { code in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            scanner.stop()
            onCode(code)
            dismiss()
        }
        scanner.start()
    }
}

#Preview {
    QRScanSheet(desktop: false, onCode: { _ in })
}
