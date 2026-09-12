//
//  QRCaptureView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

/// UIView whose backing layer is an AVCaptureVideoPreviewLayer.
class QRCapturePreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let preview = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("Expected AVCaptureVideoPreviewLayer, got \(type(of: layer))")
        }
        return preview
    }
}

/// SwiftUI bridge for an AVCaptureSession that detects QR codes.
///
/// Detection is continuous: every frame's decoded QR strings are delivered
/// (there may be several codes in view at once) and the consumer decides
/// when to stop listening — pausing/resuming lives in `QRScannerViewModel`,
/// not here.
struct QRCaptureView: UIViewRepresentable {
    let onQRCodesDetected: ([String]) -> Void
    let onCameraUnavailable: () -> Void
    @Binding var torchOn: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onQRCodesDetected: onQRCodesDetected, onCameraUnavailable: onCameraUnavailable)
    }

    func makeUIView(context: Context) -> QRCapturePreviewView {
        let view = QRCapturePreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.setup(previewLayer: view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: QRCapturePreviewView, context: Context) {
        context.coordinator.setTorch(on: torchOn)
    }

    static func dismantleUIView(_ uiView: QRCapturePreviewView, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onQRCodesDetected: ([String]) -> Void
        private let onCameraUnavailable: () -> Void
        private var captureSession: AVCaptureSession?
        private var metadataOutput: AVCaptureMetadataOutput?
        private let sessionQueue = DispatchQueue(label: "org.dash.wallet.qr-capture")

        init(onQRCodesDetected: @escaping ([String]) -> Void, onCameraUnavailable: @escaping () -> Void) {
            self.onQRCodesDetected = onQRCodesDetected
            self.onCameraUnavailable = onCameraUnavailable
        }

        deinit {
            // Nil out the delegate immediately to prevent callbacks to a deallocated coordinator.
            // AVCaptureMetadataOutput does not retain its delegate — without this, the session
            // can deliver metadata to a dangling pointer between deinit and session.stopRunning().
            metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)
            let session = captureSession
            sessionQueue.async {
                session?.stopRunning()
            }
        }

        func setup(previewLayer: AVCaptureVideoPreviewLayer) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureAndStart(previewLayer: previewLayer)
            case .notDetermined:
                // The OS permission dialog resigns the app active; these
                // notifications keep the auto-lock from engaging over it.
                NotificationCenter.default.post(name: Notification.Name.willRequestOSPermission, object: nil)
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name.didRequestOSPermission, object: nil)
                    }
                    if granted {
                        self?.configureAndStart(previewLayer: previewLayer)
                    } else {
                        DispatchQueue.main.async { self?.onCameraUnavailable() }
                    }
                }
            default:
                DispatchQueue.main.async { [weak self] in self?.onCameraUnavailable() }
            }
        }

        func stopSession() {
            // Nil out the delegate BEFORE stopping to prevent callbacks to a deallocated coordinator.
            // AVCaptureMetadataOutput holds an unretained reference to its delegate — if the
            // coordinator is deallocated while the session is still running, the delegate becomes
            // a dangling pointer and the next metadata callback causes EXC_BAD_ACCESS.
            metadataOutput?.setMetadataObjectsDelegate(nil, queue: nil)
            metadataOutput = nil

            let session = captureSession
            captureSession = nil
            sessionQueue.async {
                session?.stopRunning()
            }
        }

        func setTorch(on: Bool) {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                #if DEBUG
                DWLogger.log("QR Scanner: Torch toggle failed: \(error.localizedDescription)")
                #endif
            }
        }

        // MARK: - AVCaptureMetadataOutputObjectsDelegate

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            let values = metadataObjects.compactMap { object -> String? in
                guard let code = object as? AVMetadataMachineReadableCodeObject,
                      code.type == .qr,
                      let value = code.stringValue,
                      !value.isEmpty else { return nil }
                return value
            }
            guard !values.isEmpty else { return }
            onQRCodesDetected(values)
        }

        // MARK: - Private

        private func configureAndStart(previewLayer: AVCaptureVideoPreviewLayer) {
            sessionQueue.async { [weak self] in
                guard let self else { return }

                let session = AVCaptureSession()

                guard let device = AVCaptureDevice.default(for: .video) else {
                    DispatchQueue.main.async { self.onCameraUnavailable() }
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        DispatchQueue.main.async { self.onCameraUnavailable() }
                        return
                    }
                    session.addInput(input)
                } catch {
                    DispatchQueue.main.async { self.onCameraUnavailable() }
                    return
                }

                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    DispatchQueue.main.async { self.onCameraUnavailable() }
                    return
                }
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]

                self.metadataOutput = output

                self.captureSession = session

                // Assigning the preview layer's session commits a
                // configuration transaction on the main thread
                // (`-[AVCaptureSession commitConfiguration]`), while
                // `startRunning()` mutates the same session on `sessionQueue`.
                // Running the two concurrently races the session's internal
                // configuration lock and AVFoundation throws from
                // `startRunning` — an uncaught ObjC exception that aborts the
                // app (reported as "Crash when tapping the Scan icon on Dex").
                // Serialize them: assign the preview session on main, then hop
                // back to `sessionQueue` to start, so they never overlap.
                DispatchQueue.main.async {
                    previewLayer.session = session
                    self.sessionQueue.async {
                        session.startRunning()
                    }
                }
            }
        }
    }
}
