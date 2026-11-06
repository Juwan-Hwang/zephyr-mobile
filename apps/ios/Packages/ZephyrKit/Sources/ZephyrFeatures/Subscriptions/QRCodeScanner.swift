// QRCodeScanner — AVFoundation 二维码扫描封装。
//
// - 权限：authorizationStatus / requestAccess，结果映射为 Permission。
// - 会话在专用串行队列上配置与启停（startRunning 会阻塞，不能放主线程）。
// - 识别到二维码后回主线程回调一次（同一内容去重），由调用方决定 stop。
// - 模拟器 / 无摄像头设备：configure 返回 .unavailable。
// 需要 App 的 Info.plist 提供 NSCameraUsageDescription（X 负责，见 NOTES-L）。

import AVFoundation
import UIKit

final class QRCodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    enum Permission: Equatable { case undetermined, granted, denied, unavailable }

    /// 预览图层（主线程使用）。
    let session = AVCaptureSession()
    /// 识别结果（主线程）。
    var onCode: (@MainActor (String) -> Void)?

    private let queue = DispatchQueue(label: "zephyr.qr.session")
    private var configured = false
    private var lastCode: String?

    static var permission: Permission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    static func requestPermission() async -> Permission {
        let ok = await AVCaptureDevice.requestAccess(for: .video)
        return ok ? .granted : .denied
    }

    /// 配置输入输出（只做一次）。返回 false 表示设备没有可用摄像头。
    func configure() async -> Bool {
        await withCheckedContinuation { cont in
            queue.async {
                if self.configured { cont.resume(returning: true); return }
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    cont.resume(returning: false); return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
                    cont.resume(returning: false); return
                }
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: self.queue)
                if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
                self.session.commitConfiguration()
                self.configured = true
                cont.resume(returning: true)
            }
        }
    }

    func start() {
        queue.async {
            self.lastCode = nil
            if self.configured, !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    // MARK: AVCaptureMetadataOutputObjectsDelegate（在 queue 上回调）

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr, let value = obj.stringValue, value != lastCode else { return }
        lastCode = value
        Task { @MainActor [weak self] in self?.onCode?(value) }
    }
}
