import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(
        _ uiView: PreviewView,
        context: Context
    ) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.updateOrientation()
    }
}

final class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupOrientationNotifications()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        setupOrientationNotifications()
    }

    private func setupOrientationNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func deviceOrientationDidChange() {
        updateOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = previewLayer.connection else { return }

        let deviceOrientation = UIDevice.current.orientation

        if #available(iOS 17.0, *) {
            let angle: CGFloat
            switch deviceOrientation {
            case .portrait:
                angle = 90.0
            case .landscapeRight:
                angle = 180.0
            case .landscapeLeft:
                angle = 0.0
            case .portraitUpsideDown:
                angle = 270.0
            default:
                angle = 90.0
            }

            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            guard connection.isVideoOrientationSupported else { return }
            let videoOrientation: AVCaptureVideoOrientation
            switch deviceOrientation {
            case .portrait:
                videoOrientation = .portrait
            case .landscapeRight:
                videoOrientation = .landscapeLeft
            case .landscapeLeft:
                videoOrientation = .landscapeRight
            case .portraitUpsideDown:
                videoOrientation = .portraitUpsideDown
            default:
                videoOrientation = .portrait
            }

            if connection.videoOrientation != videoOrientation {
                connection.videoOrientation = videoOrientation
            }
        }
    }
}
