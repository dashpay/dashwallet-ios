//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - QRScanPreviewView

/// The camera picture under the payment scanner, and the outline of the code
/// it found.
///
/// The one part of the scanner that has to stay a `UIView`: the live picture
/// is an `AVCaptureVideoPreviewLayer`, and SwiftUI has no view for it.
///
/// Two layers, as before. The preview layer shows the session live. The
/// sample-buffer layer above it shows the same frames, fed by
/// `DWCaptureSessionManager` through `DWCaptureSessionFrameDelegate`; while a
/// code is being handled it stops taking frames, so the picture freezes on
/// the code with its outline drawn on it — green while it is being read,
/// red when it is not a Dash payment.
final class QRScanPreviewView: UIView, DWCaptureSessionFrameDelegate {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var codeLayer: CAShapeLayer?

    /// Set from the capture queue's callback and the main thread both.
    private let pauseLock = NSLock()
    private var _pausesFrames = false
    private var pausesFrames: Bool {
        get { pauseLock.lock(); defer { pauseLock.unlock() }; return _pausesFrames }
        set { pauseLock.lock(); _pausesFrames = newValue; pauseLock.unlock() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .black

        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        sampleBufferDisplayLayer.videoGravity = .resizeAspectFill
        sampleBufferDisplayLayer.opacity = 0.95
        layer.addSublayer(sampleBufferDisplayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        sampleBufferDisplayLayer.frame = bounds
    }

    func connect(_ session: AVCaptureSession) {
        previewLayer.session = session
    }

    func disconnect() {
        previewLayer.session = nil
    }

    /// Freezes the picture on a found code and outlines it, or clears both.
    func show(_ code: QRCodeObject?) {
        pausesFrames = code != nil

        guard let code else {
            codeLayer?.removeFromSuperlayer()
            codeLayer = nil
            return
        }

        if codeLayer == nil {
            let shape = CAShapeLayer()
            shape.path = outline(of: code)
            shape.lineJoin = .round
            shape.lineWidth = 4
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sampleBufferDisplayLayer.addSublayer(shape)
            CATransaction.commit()
            codeLayer = shape
        }

        let color: UIColor
        switch code.type {
        case .paymentRequestFailed, .invalid:
            color = UIColor(Color.dash.red)
        default:
            color = UIColor(Color.dash.green)
        }
        codeLayer?.strokeColor = color.withAlphaComponent(0.7).cgColor
        codeLayer?.fillColor = color.withAlphaComponent(0.3).cgColor
    }

    private func outline(of code: QRCodeObject) -> CGPath {
        let path = CGMutablePath()
        guard let transformed = previewLayer.transformedMetadataObject(for: code.metadataObject)
            as? AVMetadataMachineReadableCodeObject,
            let first = transformed.corners.first else {
            return path
        }
        path.move(to: first)
        transformed.corners.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    // MARK: DWCaptureSessionFrameDelegate

    func didOutputSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard !pausesFrames else { return }

        if sampleBufferDisplayLayer.status == .failed {
            sampleBufferDisplayLayer.flush()
        }
        sampleBufferDisplayLayer.enqueue(sampleBuffer)
    }
}

// MARK: - QRScanPreview

/// `QRScanPreviewView` for SwiftUI. The view itself is owned by
/// `QRScanViewModel`, which connects the capture session to it once the
/// camera has started — so it is handed in, not created here.
struct QRScanPreview: UIViewRepresentable {
    let view: QRScanPreviewView

    func makeUIView(context: Context) -> QRScanPreviewView { view }
    func updateUIView(_ uiView: QRScanPreviewView, context: Context) { }
}
