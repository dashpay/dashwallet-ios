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

    /// Scan-routing prefill (`DWBasePayViewController`'s ObjC scan handler):
    /// a scanned bech32m Platform/Shielded destination opens this screen
    /// with the address (and BIP21 amount, when present) applied on load.
    @objc func prefill(address: String, amountDuffs: UInt64) {
        prefillAddress = address
        prefillAmountDuffs = amountDuffs
    }

    private var prefillAddress: String?
    private var prefillAmountDuffs: UInt64 = 0

    private let sendViewModel = SendViewModel()
    private lazy var hostingController: UIHostingController<SendScreen> = {
        var screen = SendScreen(
            viewModel: sendViewModel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onScanQR: { [weak self] in self?.performScanQRCodeAction() },
            onContinue: { [weak self] in
                guard let self else { return }
                self.pushExternalSendSource(
                    viewModel: self.sendViewModel,
                    onSendCompleted: { [weak self] in self?.dismiss(animated: true) })
            })
        // Pushed from the payments landing there is somewhere to go back to;
        // presented as the "Send to Address" shortcut there is not.
        if let navigationController, navigationController.viewControllers.first !== self {
            screen.onBack = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        }
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
        if let prefillAddress {
            sendViewModel.addressText = prefillAddress
            if prefillAmountDuffs > 0 {
                sendViewModel.unit = .dash
                sendViewModel.amountText = prefillAmountDuffs.formattedDashAmountWithoutCurrencySymbol
            }
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

    /// Push the external-send SOURCE step (From picker) onto the current
    /// navigation stack, sharing the address step's view model. Continue there
    /// pushes the amount step. Shared by the Send screen and the balance-row
    /// send sheet (both `DWBasePayViewController` hosts inside a nav
    /// controller).
    func pushExternalSendSource(viewModel: SendViewModel,
                                onSendCompleted: @escaping () -> Void) {
        let screen = SendSourceScreen(
            viewModel: viewModel,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onContinue: { [weak self] in
                guard let self else { return }
                // Every source lands on the same amount step, Transparent
                // included. Core → Core still finishes in the L1 payment
                // processor for the real fee math and its confirm, but it
                // gets there from that step carrying the amount, rather than
                // being handed off before one is entered.
                self.pushExternalSendAmount(viewModel: viewModel, onSendCompleted: onSendCompleted)
            })
        // Every UIHostingController already conforms to NavigationBarDisplayable
        // (nav bar + back button hidden); the screen draws its own back + title.
        let host = UIHostingController(rootView: screen)
        navigationController?.pushViewController(host, animated: true)
    }

    /// Push the external-send AMOUNT step (final). Core → Core rides
    /// `continueCore` (the L1 payment processor); every other route confirms in
    /// `SendConfirmSheet`.
    func pushExternalSendAmount(viewModel: SendViewModel,
                                onSendCompleted: @escaping () -> Void) {
        let screen = ExternalSendAmountScreen(
            viewModel: viewModel,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onContinueCore: { [weak self] address, amountDuffs in
                self?.continueCore(address: address, amountDuffs: amountDuffs)
            },
            onSendCompleted: onSendCompleted)
        let host = UIHostingController(rootView: screen)
        navigationController?.pushViewController(host, animated: true)
    }
}

// MARK: NavigationBarDisplayable

// The screen draws its own X + title header. When it is the root of its own
// modal (the "Send to Address" shortcut), BaseNavigationController's willShow
// pass must not re-show the (empty) navigation bar above it. Pushed from the
// payments landing the bar stays hidden too — `SendScreen` draws the design
// system's own `NavigationBar`, with back in place of close.
extension SendScreenViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}
