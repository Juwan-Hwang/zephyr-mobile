// QRScannerView — 摄像头预览（AVCaptureVideoPreviewLayer）挂进 SwiftUI。

import AVFoundation
import SwiftUI
import UIKit

struct QRScannerView: UIViewRepresentable {
    let scanner: QRCodeScanner

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = scanner.session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        v.isAccessibilityElement = true
        v.accessibilityLabel = "相机取景框"
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
