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
struct QRCaptureView: UIViewRepresentable {
    let onQRCodeScanned: (String) -> Void
    let onCameraUnavailable: () -> Void
    @Binding var torchOn: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onQRCodeScanned: onQRCodeScanned, onCameraUnavailable: onCameraUnavailable)
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
        private let onQRCodeScanned: (String) -> Void
        private let onCameraUnavailable: () -> Void
        private var captureSession: AVCaptureSession?
        private var metadataOutput: AVCaptureMetadataOutput?
        private let sessionQueue = DispatchQueue(label: "com.dashwallet.maya.qr-capture")
        private var hasScanned = false

        init(onQRCodeScanned: @escaping (String) -> Void, onCameraUnavailable: @escaping () -> Void) {
            self.onQRCodeScanned = onQRCodeScanned
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
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
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
                DSLogger.log("Maya QR Scanner: Torch toggle failed: \(error.localizedDescription)")
                #endif
            }
        }

        // MARK: - AVCaptureMetadataOutputObjectsDelegate

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue,
                  !value.isEmpty else {
                return
            }

            hasScanned = true
            onQRCodeScanned(value)
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

                DispatchQueue.main.async {
                    previewLayer.session = session
                }

                self.captureSession = session
                session.startRunning()
            }
        }
    }
}
