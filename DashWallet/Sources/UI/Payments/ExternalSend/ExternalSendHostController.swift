//
//  Created by Roman Chornyi
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

import SwiftUI
import UIKit

/// The UIKit side of `ExternalSendFlow`: the host for `ExternalSendFlowScreen` (a step pushed in the Payments sheet,
/// or full screen when presented), the QR scanner behind the address field's scan button, and what each way the flow
/// finishes does to the screens around it.
final class ExternalSendHostController: UIHostingController<ExternalSendFlowScreen> {
    private let flow: ExternalSendFlow
    private weak var anchor: UIViewController?

    init(flow: ExternalSendFlow) {
        self.flow = flow
        super.init(rootView: ExternalSendFlowScreen(flow: flow, onScan: {}))
        modalPresentationStyle = .fullScreen
        rootView.onScan = { [weak self] in self?.presentScanner() }
        flow.onFinish = { [weak self] in self?.handle($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The host for a send that starts on the Address screen, with `source` pinned when a balance row opened it.
    static func addressHost(pinned source: SendSource?) -> ExternalSendHostController {
        let flow = ExternalSendFlow()
        if let source { flow.start(pinned: source) } else { flow.start() }
        return ExternalSendHostController(flow: flow)
    }

    /// The host a scan or a link is opening; another scan or link meanwhile opens nothing.
    private static weak var opening: ExternalSendHostController?

    /// Opens Send for a scanned code or a dash: link over `presenter`. The host shows at once, on Address while an
    /// Identity ID is checked or a payment request is fetched; `prefetched` is the request the scanner already
    /// fetched; `openedByApp` when another app opened the link. Text that is not valid here presents nothing and shows
    /// the invalid-address alert. `requestCleared` when the scanner's fetch of the code's request failed and it fell
    /// back to the code's own Core address: the request is not fetched again.
    static func present(scanned text: String, prefetched: PaymentRequestDetails? = nil, openedByApp: Bool = false,
                        requestCleared: Bool = false, from presenter: UIViewController) {
        guard opening == nil else { return }
        let anchor = presenter.topController()
        let flow = ExternalSendFlow()
        // Checked before presenting: a dismiss while the host is still animating in would be dropped.
        guard flow.scannedDestination(text, openedByApp: openedByApp, requestCleared: requestCleared) != nil else {
            presentInvalidAddressAlert(on: anchor)
            return
        }
        flow.start()
        let host = ExternalSendHostController(flow: flow)
        opening = host
        host.anchor = anchor
        // Started once the host is on screen: a request that fails fast alerts on the host, and an alert presented
        // while the host is still animating in would be dropped.
        anchor.present(host, animated: true) {
            Task { @MainActor in
                _ = await host.flow.handleScanned(
                    text, prefetched: prefetched, openedByApp: openedByApp, requestCleared: requestCleared)
                opening = nil
            }
        }
    }

    private static func presentInvalidAddressAlert(on presenter: UIViewController) {
        let alert = UIAlertController(
            title: NSLocalizedString("Not a valid Dash address", comment: ""), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        presenter.present(alert, animated: true)
    }

    // MARK: - Finishing

    private func handle(_ finish: ExternalSendFlow.Finish) {
        switch finish {
        case .backToMenu:
            leave()
        case .closed:
            switch flow.step {
            case .sent, .sendFailed: dismissAll()
            default: leave()
            }
        case let .toast(title, message):
            let text = Self.toastText(title: title, message: message)
            dismissAll { $0.presentDashUIKitToast(style: .info, message: text) }
        case let .requestFailed(title, message):
            presentRequestFailedAlert(title: title, message: message)
        case let .success(view, txidWire, callbackURL):
            if let callbackURL { UIApplication.shared.open(callbackURL) }
            showSuccess(view, txidWire: txidWire)
        }
    }

    private func showSuccess(_ view: SendSuccessView, txidWire: Data?) {
        switch view {
        case .transactionDetails:
            if let txidWire { presentTransactionDetails(txidWire: txidWire) }
        case .toast(let message):
            dismissAll { $0.presentDashUIKitToast(style: .success, message: message) }
        }
    }

    /// The Toast has one text line, so the title leads the message; VoiceOver reads the two as one label.
    static func toastText(title: String, message: String) -> String {
        guard !title.isEmpty else { return message }
        let endsSentence = title.last.map { ".!?".contains($0) } ?? false
        return title + (endsSentence ? " " : ". ") + message
    }

    private func presentRequestFailedAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        // A pushed Address stays open to correct the entry; a host opened for a scan or link closes.
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel) { [weak self] _ in
            guard let self, !self.isPushed, self.presentingViewController != nil else { return }
            self.dismissAll()
        })
        (isPushed || presentingViewController != nil ? self : anchor)?.present(alert, animated: true)
    }

    private func presentTransactionDetails(txidWire: Data) {
        let showDetails = { [weak self] in
            guard let self else { return }
            let controller = SuccessTxDetailViewController(model: TxDetailModel(txidWire: txidWire))
            controller.delegate = self
            self.present(controller, animated: true)
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: showDetails)
        } else {
            showDetails()
        }
    }

    /// Pushed as a step of the Payments sheet, or presented on its own.
    private var isPushed: Bool {
        guard let navigationController else { return false }
        return navigationController.viewControllers.first !== self
    }

    /// Back to where the flow was opened: pops the step, or dismisses the presented host.
    private func leave() {
        if isPushed {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    /// Dismisses every modal below this host as well, so the Payments sheet the flow was opened from goes with it.
    /// A host pushed on a navigation stack that stays (the Payments tab) is popped too, and `completion` then gets
    /// that navigation controller rather than the popped host.
    private func dismissAll(then completion: ((UIViewController) -> Void)? = nil) {
        var root: UIViewController = self
        while let presenter = root.presentingViewController { root = presenter }
        let pushedOn = isPushed ? navigationController : nil
        let finish = { [weak self] in
            if let pushedOn, let self, let index = pushedOn.viewControllers.firstIndex(of: self) {
                pushedOn.popToViewController(pushedOn.viewControllers[index - 1], animated: false)
            }
            completion?(root === self ? (pushedOn ?? root) : root)
        }
        guard root.presentedViewController != nil else {
            finish()
            return
        }
        root.dismiss(animated: true, completion: finish)
    }

    // MARK: - Scanner

    private func presentScanner() {
        guard !(presentedViewController is DWQRScanViewController) else { return }
        let scanner = DWQRScanViewController()
        scanner.model.delegate = self
        present(scanner, animated: true)
    }
}

extension ExternalSendHostController: DWQRScanModelDelegate {
    func qrScanModel(_ viewModel: DWQRScanModel, didScanPaymentInput paymentInput: DWPaymentInput) {
        guard let text = paymentInput.parsedURI?.rawString else {
            dismiss(animated: true) { [weak self] in self.map(Self.presentInvalidAddressAlert) }
            return
        }
        // The scanner closes first, so Address shows its checking state while the scan is resolved.
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let accepted = await self.flow.handleScanned(
                    text, prefetched: paymentInput.prefetchedRequest, requestCleared: paymentInput.requestCleared)
                if !accepted { Self.presentInvalidAddressAlert(on: self) }
            }
        }
    }

    func qrScanModelDidCancel(_ viewModel: DWQRScanModel) {
        dismiss(animated: true)
    }
}

extension ExternalSendHostController: SuccessTxDetailViewControllerDelegate {
    func txDetailViewControllerDidFinish(controller: SuccessTxDetailViewController) {
        dismissAll()
    }
}

/// The entry points the ObjC payment screens call.
@objc(DWExternalSendLauncher)
final class ExternalSendLauncher: NSObject {
    /// A scanned QR code: the text it was read from, tried by the new destination parser.
    @objc
    static func presentScanned(_ input: DWPaymentInput, from presenter: UIViewController) {
        ExternalSendHostController.present(
            scanned: input.parsedURI?.rawString ?? "", prefetched: input.prefetchedRequest,
            requestCleared: input.requestCleared, from: presenter)
    }

    /// A dash: link from another app.
    @objc
    static func presentLink(_ url: URL, from presenter: UIViewController) {
        ExternalSendHostController.present(scanned: url.absoluteString, openedByApp: true, from: presenter)
    }
}

private extension DWPaymentInput {
    /// The scanner's fetch of the code's request failed: it attached the code with its request URL cleared
    /// (`uriByClearingRequestURL`), though the raw text still carries `r=`.
    var requestCleared: Bool {
        guard let parsed = parsedURI, parsed.rURL == nil else { return false }
        return BIP70URI(ParsedPaymentURI.paymentString(for: parsed.rawString))?.r != nil
    }

    /// The payment request the scanner fetched and verified with the code.
    var prefetchedRequest: PaymentRequestDetails? {
        (bip70Confirmation as? BIP70ConfirmationBox).flatMap(PaymentRequestDetails.init(box:))
    }
}

extension SendSource {
    /// The source a balance row's Send pins.
    init(_ network: ChainNetwork) {
        switch network {
        case .core: self = .core
        case .platform: self = .platform
        case .shielded: self = .shielded
        }
    }
}
