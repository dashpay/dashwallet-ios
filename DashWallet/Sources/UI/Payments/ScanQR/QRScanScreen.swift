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

import Combine
import SwiftUI

// MARK: - QRScanViewModel

/// What the payment scanner shows, read off `DWQRScanModel`.
///
/// `DWQRScanModel` keeps doing the work — the camera session, picking the
/// Dash code among those in view, fetching a BIP70 request, handing the
/// result to its delegate. This only turns the code it is holding into
/// something SwiftUI can observe, and owns the camera view.
final class QRScanViewModel: ObservableObject {
    enum Status: Equatable {
        case none
        case connecting
        case invalidPaymentRequest(message: String?)
        case invalidQR(message: String?)
    }

    @Published private(set) var status: Status = .none
    @Published var showsCameraDeniedAlert = false

    let model: DWQRScanModel
    let previewView = QRScanPreviewView()
    let isTorchAvailable = DWQRScanModel.isTorchAvailable

    private var codeObserver: NSKeyValueObservation?
    private var typeObserver: NSKeyValueObservation?

    init(model: DWQRScanModel) {
        self.model = model
        model.frameDelegate = previewView

        codeObserver = model.observe(\.qrCodeObject, options: [.initial, .new]) { [weak self] model, _ in
            self?.observe(model.qrCodeObject)
        }
    }

    /// Starts the camera, unless access was refused — then says so.
    func start() {
        guard !model.isCameraDeniedOrRestricted else {
            showsCameraDeniedAlert = true
            return
        }

        NotificationCenter.default.post(name: .willRequestOSPermission, object: nil)
        model.startPreviewCompletion { [weak self] in
            NotificationCenter.default.post(name: .didRequestOSPermission, object: nil)
            guard let self else { return }
            self.previewView.connect(self.model.captureSession)
        }
    }

    func stop() {
        previewView.disconnect()
        model.stopPreview()
    }

    func cancel() { model.cancel() }
    func switchTorch() { model.switchTorch() }

    /// A code's state changes after it is found — a BIP70 request goes from
    /// connecting to failed — so its `type` is watched as well.
    private func observe(_ code: QRCodeObject?) {
        typeObserver = code?.observe(\.type, options: [.new]) { [weak self] code, _ in
            DispatchQueue.main.async { self?.update(with: code) }
        }
        update(with: code)
    }

    private func update(with code: QRCodeObject?) {
        guard code === model.qrCodeObject else { return }
        previewView.show(code)

        switch code?.type {
        case .validPaymentRequest:
            status = .connecting
        case .paymentRequestFailed:
            status = .invalidPaymentRequest(message: code?.errorMessage)
        case .invalid:
            status = .invalidQR(message: code?.errorMessage)
        default:
            status = .none
        }
    }
}

// MARK: - QRScanScreen

/// Scan a Dash payment code: the camera picture with a frame to aim at, what
/// became of the code it found, and Cancel / torch at the bottom.
struct QRScanScreen: View {
    @ObservedObject var viewModel: QRScanViewModel

    /// The aiming frame's height, for hanging the status card below it.
    private static let frameHeight = UIImage(named: "qr_frame")?.size.height ?? 0

    var body: some View {
        ZStack {
            QRScanPreview(view: viewModel.previewView)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            // The frame sits in the middle of the screen whether or not there
            // is a status; the card hangs 16pt below it.
            // An overlay, so the card takes no part in laying the frame out.
            Image("qr_frame")
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if viewModel.status != .none {
                        GeometryReader { geometry in
                            QRScanStatusCard(status: viewModel.status)
                                .padding(.horizontal, 16)
                                .padding(.top, geometry.size.height / 2 + Self.frameHeight / 2 + 16)
                        }
                    }
                }
                .ignoresSafeArea()

            VStack {
                Spacer()
                toolbar
            }
        }
        .background(Color.black.ignoresSafeArea())
        .alert(cameraDeniedTitle, isPresented: $viewModel.showsCameraDeniedAlert) {
            Button(String(localized: "Cancel", comment: ""), role: .cancel) { }
            Button(String(localized: "Settings", comment: "")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(String(localized: "Allow camera access in Settings", comment: ""))
        }
    }

    private var cameraDeniedTitle: String {
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? ""
        return String(localized: "\(appName) is not allowed to access the camera", comment: "")
    }

    /// Cancel, and the torch where the device has one — then the two sit at
    /// the edges; alone, Cancel is centred, as the system toolbar it replaces
    /// laid it out.
    private var toolbar: some View {
        HStack {
            if viewModel.isTorchAvailable {
                cancelButton
                Spacer()
                toolbarButton(image: "icon_qr_flash",
                              label: String(localized: "Flashlight", comment: "QR scanner"),
                              action: viewModel.switchTorch)
            } else {
                cancelButton
            }
        }
        .padding(.horizontal, 20)
    }

    private var cancelButton: some View {
        toolbarButton(image: "icon_qr_cancel",
                      label: String(localized: "Cancel", comment: ""),
                      action: viewModel.cancel)
    }

    private func toolbarButton(image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image)
                .renderingMode(.template)
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - QRScanStatusCard

/// Under the frame: "please wait" while a BIP70 request is fetched, or why
/// the code can't be paid. Scanning resumes on its own a moment later.
private struct QRScanStatusCard: View {
    let status: QRScanViewModel.Status

    var body: some View {
        VStack(spacing: 0) {
            icon
            Text(title)
                .dashFont(.title3)
                .foregroundColor(Color.dash.primaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            Text(message)
                .dashFont(.body)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .connecting:
            // The old four-frame "connecting" animation, 0.75s a cycle.
            TimelineView(.periodic(from: .now, by: 0.15)) { context in
                let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.15) % 5
                Image("connection_animation_\(frame == 4 ? 1 : frame + 1)")
            }
        case .invalidPaymentRequest:
            Image("unable_to_connect")
        case .invalidQR:
            Image("invalid_qr")
        case .none:
            EmptyView()
        }
    }

    private var title: String {
        switch status {
        case .connecting: return String(localized: "Please Wait", comment: "")
        case .invalidPaymentRequest: return String(localized: "Invalid Payment Request", comment: "")
        case .invalidQR: return String(localized: "Invalid QR Code", comment: "")
        case .none: return ""
        }
    }

    private var message: String {
        let retry = String(localized: "Please try scanning again", comment: "")
        switch status {
        case .connecting: return String(localized: "Connecting to payment server", comment: "")
        case let .invalidPaymentRequest(message): return message ?? retry
        case let .invalidQR(message): return message ?? retry
        case .none: return ""
        }
    }
}
