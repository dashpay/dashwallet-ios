//
//  SendScreenViewController.swift
//  DashWallet
//

import SwiftDashSDK
import SwiftUI
import UIKit

@objc(DWSendScreenViewController)
final class SendScreenViewController: DWBasePayViewController {

    /// Set by the "Send to Address" shortcut entry: on load, a valid address
    /// on the clipboard is applied to the address field directly — the same
    /// action as tapping the clipboard suggestion chip.
    var prefillsFromClipboard = false

    private let sendViewModel = SendViewModel()
    private lazy var hostingController: UIHostingController<SendScreen> = {
        let screen = SendScreen(
            viewModel: sendViewModel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onScanQR: { [weak self] in self?.performScanQRCodeAction() },
            onContinueCore: { [weak self] address, amountDuffs in
                self?.continueCore(address: address, amountDuffs: amountDuffs)
            },
            onSendCompleted: { [weak self] in self?.dismiss(animated: true) })
        return UIHostingController(rootView: screen)
    }()

    override func viewDidLoad() {
        if payModel == nil {
            payModel = DWPayModel()
        }
        super.viewDidLoad()
        view.backgroundColor = .dw_background()

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)

        if prefillsFromClipboard {
            sendViewModel.useClipboardSuggestion()
        }
    }

    // MARK: - QR scan

    /// The base class routes a scanned payment straight into the payment
    /// processor (its `DWQRScanModelDelegate` conformance is a private
    /// class extension, so this can't be `override` — the matching selector
    /// shadows it through ObjC dispatch). On this screen a scan fills the
    /// form instead, so the destination-type detection and From picker
    /// apply to scanned addresses exactly like typed/pasted ones.
    @objc(qrScanModel:didScanPaymentInput:)
    func qrScanModel(_ viewModel: DWQRScanModel, didScanPaymentInput paymentInput: DWPaymentInput) {
        dismiss(animated: true) { [weak self] in
            self?.sendViewModel.ingestScannedInput(paymentInput)
        }
    }
}

// MARK: - Core → Core routing

extension DWBasePayViewController {
    /// Core L1 send with a fixed amount: a BIP21 `dash:` URI carries the
    /// amount into the classic payment processor, which goes straight to
    /// its confirm (real fee math) — the amount screen is skipped because
    /// the intent already has an amount. Shared by the Send screen and the
    /// balance-row send sheet.
    func continueCore(address: String, amountDuffs: UInt64) {
        guard address.isValidDashAddressForCurrentNetwork else { return }
        var uriString = "dash:\(address)"
        if amountDuffs > 0 {
            let dashAmount = InternalTransferViewModel.formatTyped(
                amountDuffs.dashAmount, fractionDigits: 8)
            uriString += "?amount=\(dashAmount)"
        }
        guard let url = URL(string: uriString) else { return }
        performPay(to: url)
    }
}

// MARK: NavigationBarDisplayable

// The screen draws its own X + title header. When it is the root of its own
// modal (the "Send to Address" shortcut), BaseNavigationController's willShow
// pass must not re-show the (empty) navigation bar above it. Pushed from the
// payments landing it keeps the bar's back arrow, as before.
extension SendScreenViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { navigationController?.viewControllers.first === self }
    var isNavigationBarHidden: Bool { navigationController?.viewControllers.first === self }
}
