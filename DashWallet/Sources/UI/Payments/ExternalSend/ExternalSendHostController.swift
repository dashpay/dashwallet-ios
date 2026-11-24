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
/// finishes does to the screens around it. Every way the host leaves the screen closes the flow.
final class ExternalSendHostController: UIHostingController<ExternalSendFlowScreen> {
    private let flow: ExternalSendFlow

    init(flow: ExternalSendFlow) {
        self.flow = flow
        super.init(rootView: ExternalSendFlowScreen(flow: flow, onScan: {}))
        modalPresentationStyle = .fullScreen
        rootView.onScan = { [weak self] in self?.presentScanner() }
        flow.onFinish = { [weak self] in self?.handle($0) }
        flow.onRequestFailed = { [weak self] in self?.presentRequestFailedAlert($0) }
    }

    /// A swipe, a pop, or a dismissal of the screens below it: the flow ends with the host, so a scan or link
    /// it was opening no longer holds the next one. A finish that caused the dismissal already ended the flow.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isLeavingForGood else { return }
        flow.onFinish = nil
        flow.close()
    }

    /// Popped, or dismissed itself or with a controller below it; not merely covered by a screen it presented.
    private var isLeavingForGood: Bool {
        var current: UIViewController? = self
        while let controller = current {
            if controller.isBeingDismissed || controller.isMovingFromParent { return true }
            current = controller.parent ?? controller.presentingViewController
        }
        return false
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

    /// The flow of the last scan or link; while it is opening, another scan or link opens nothing. It stops opening
    /// once the input reached a screen, its request failed, or the flow ended with its host.
    private static weak var opening: ExternalSendFlow?

    /// Opens Send for a scanned code or a dash: link over `presenter`. The host shows at once, on Address while an
    /// Identity ID is checked or a payment request is fetched. A scan or link that read into no input (nil) presents
    /// nothing and shows the invalid-address alert.
    static func present(_ input: ScanInput?, from presenter: UIViewController) {
        guard opening?.isOpening != true else { return }
        let anchor = presenter.topController()
        // Checked before presenting: a dismiss while the host is still animating in would be dropped.
        guard let input else {
            presentInvalidAddressAlert(on: anchor)
            return
        }
        let flow = ExternalSendFlow()
        let host = ExternalSendHostController(flow: flow)
        flow.open(input)
        opening = flow
        anchor.present(host, animated: true)
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
            case .sent, .sendFailed, .lockHeld: dismissAll()
            default: leave()
            }
        case let .toast(title, message):
            let text = Self.toastText(title: title, message: message)
            dismissAll { $0.presentDashUIKitToast(style: .info, message: text) }
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

    /// Address stays open under the alert to correct the entry.
    private func presentRequestFailedAlert(_ failure: ExternalSendFlow.RequestFailure) {
        let alert = UIAlertController(title: failure.title, message: failure.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        // An alert presented while the host is still animating in would be dropped, so it waits for the transition.
        guard let transition = transitionCoordinator else { return present(alert, animated: true) }
        transition.animate(alongsideTransition: nil) { [weak self] _ in self?.present(alert, animated: true) }
    }

    private func presentTransactionDetails(txidWire: Data) {
        let showDetails = { [weak self] in
            guard let self else { return }
            let controller = SuccessTxDetailViewController(model: TxDetailModel(txidWire: txidWire))
            controller.delegate = self
            Self.presentsTransactionDetails(controller)
            self.present(controller, animated: true)
        }
        if let presented = presentedViewController {
            presented.dismiss(animated: true, completion: showDetails)
        } else {
            showDetails()
        }
    }

    /// Full screen, as `MainTabbarController.presentTxDetails` shows them: a sheet could be swiped away without its
    /// Close, which is what ends the flow's screens (`dismissAll`).
    static func presentsTransactionDetails(_ controller: UIViewController) {
        controller.modalPresentationStyle = .fullScreen
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
        guard let input = ScanInput(paymentInput) else {
            dismiss(animated: true) { [weak self] in self.map(Self.presentInvalidAddressAlert) }
            return
        }
        // The scanner closes first, so Address shows its checking state while the scan is resolved.
        dismiss(animated: true) { [weak self] in
            self?.flow.open(input)
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
    /// A scanned QR code, in the unlocked app. A code scanned on the lock screen is held by the root and opened here
    /// after the lock screen's own unlock.
    @objc @MainActor
    static func presentScanned(_ input: DWPaymentInput, from presenter: UIViewController) {
        ExternalSendHostController.present(ScanInput(input), from: presenter)
    }

    /// A dash: link from another app, in the unlocked app: the root defers a link that arrives while it is locked.
    @objc @MainActor
    static func presentLink(_ url: URL, from presenter: UIViewController) {
        ExternalSendHostController.present(ScanInput(link: url), from: presenter)
    }
}

extension ScanInput {
    /// The scanner's input: the text the code was read from, the request it fetched and whether it cleared the
    /// code's request.
    init?(_ input: DWPaymentInput, network: WalletEnvironment.NetworkKind = WalletEnvironment.networkKind) {
        guard let text = input.parsedURI?.rawString else { return nil }
        self.init(text: text, network: network, prefetched: input.prefetchedRequest,
                  requestCleared: input.requestCleared)
    }

    /// A dash: link another app opened.
    init?(link url: URL, network: WalletEnvironment.NetworkKind = WalletEnvironment.networkKind) {
        self.init(text: url.absoluteString, network: network, openedByApp: true)
    }
}

private extension DWPaymentInput {
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
