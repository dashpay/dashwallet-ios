//
//  SendScreenViewController.swift
//  DashWallet
//

import SwiftDashSDK
import SwiftUI
import UIKit

@objc(DWSendScreenViewController)
final class SendScreenViewController: DWBasePayViewController {

    /// Set by the "Send to Address" shortcut entry: on appearance, a valid address
    /// on the clipboard is applied to the address field directly — the same
    /// action as tapping the clipboard suggestion chip.
    var prefillsFromClipboard = false

    /// Scan-routing prefill (`DWBasePayViewController`'s ObjC scan handler):
    /// a scanned bech32m Platform/Shielded destination opens this screen
    /// with the address (and BIP21 amount, when present) applied.
    @objc func prefill(address: String, amountDuffs: UInt64) {
        sendViewModel.addressText = address
        if amountDuffs > 0 {
            sendViewModel.unit = .dash
            sendViewModel.amountText = amountDuffs.formattedDashAmountWithoutCurrencySymbol
        }
    }

    /// Scan-routing prefill from the payments landing, whose Send tab is a
    /// destination picker with no form to fill: the scan opens this screen
    /// with the input already ingested, so it lands where a scan started here
    /// would. The caller checks the input is one the form can hold
    /// (`SendViewModel.scannedAddress(in:)`).
    func prefill(scannedInput: DWPaymentInput) {
        sendViewModel.ingestScannedInput(scannedInput)
    }

    /// Both scan prefills apply to the view model immediately rather than on
    /// load: the model exists before the view does, and a caller that opens
    /// the flow past this step (`makeSourceStep`) needs the destination — and
    /// therefore the valid sources — resolved in the same turn.
    ///
    /// False means the address did not decode, which only this screen can say
    /// (it draws the invalid-address message), so the caller must not skip it.
    @objc var hasResolvedDestination: Bool { sendViewModel.destination != nil }

    /// The From picker for this screen's flow, for a caller that opens the
    /// stack past the address step: a scan has already named the recipient, so
    /// showing a form whose one field is filled in is a step that asks nothing.
    ///
    /// Built here rather than by that caller so it shares this screen's view
    /// model and completion — the same two the Continue button's own push uses.
    /// Back from it (and the tap on its address summary) lands on this screen,
    /// which is where a scanned address is edited.
    @objc func makeSourceStep() -> UIViewController {
        let controller = makeExternalSendSource(
            viewModel: sendViewModel,
            onSendCompleted: { [weak self] in self?.dismiss(animated: true) })
        controller.hidesBottomBarWhenPushed = true
        return controller
    }

    /// Grants the model its pasteboard reads. The SwiftUI form below stays
    /// alive while a later send step is pushed over it, so appearance — not
    /// the form's lifetime — is what says the screen is on screen.
    private var isOnScreen = false

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

        sendViewModel.isClipboardReadAllowed = { [weak self] in self?.isOnScreen == true }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        if prefillsFromClipboard {
            prefillsFromClipboard = false
            // The form registers for reads shortly after this (its entrance
            // animation is deferred), so the intent is handed to the model
            // rather than acted on against a suggestion that cannot exist yet.
            sendViewModel.applyClipboardSuggestionWhenAvailable()
        } else {
            sendViewModel.refreshClipboardSuggestion()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isOnScreen = false
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
            guard let self else { return }
            // A BIP70 request has no address to put in the field — filling the
            // form with it is a no-op, so the scan would end nowhere. That one
            // keeps the classic processor's confirmation.
            if !self.sendViewModel.ingestScannedInput(paymentInput) {
                self.processPaymentInput(paymentInput)
            }
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
        // A plain-address input, not a `dash:` URI through `performPay(to:)`.
        // That route classifies a URI carrying a valid address as a DEEP LINK,
        // and `DWPaymentProcessor` answers a deep link by asking for an amount
        // — pushing the legacy `ProvideAmountViewController` on top of the
        // amount step the user has just filled in, prefilled with the same
        // number. Two amount screens, and the second one in the old design.
        //
        // Nothing here is a deep link: this flow already holds the address and
        // the amount. `payToAddress:amount:` puts both on a `PlainAddress`
        // input, which the processor takes straight to the confirmation with
        // the real fee — the same place Platform and Shielded land.
        performPay(toAddress: address, amount: amountDuffs)
    }

    /// Push the external-send SOURCE step (From picker) onto the current
    /// navigation stack, sharing the address step's view model. Continue there
    /// pushes the amount step. Shared by the Send screen and the balance-row
    /// send sheet (both `DWBasePayViewController` hosts inside a nav
    /// controller).
    func pushExternalSendSource(viewModel: SendViewModel,
                                onSendCompleted: @escaping () -> Void) {
        navigationController?.pushViewController(
            makeExternalSendSource(viewModel: viewModel, onSendCompleted: onSendCompleted),
            animated: true)
    }

    /// The SOURCE step as a controller, for a caller that puts it in the stack
    /// itself rather than pushing it on top of what is there — opening a
    /// scanned send on the From picker, with the address step behind it, is
    /// one animated transition rather than two stacked ones.
    func makeExternalSendSource(viewModel: SendViewModel,
                                onSendCompleted: @escaping () -> Void) -> UIViewController {
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
        return UIHostingController(rootView: screen)
    }

    /// Push the external-send AMOUNT step (final). Core → Core rides
    /// `continueCore` (the L1 payment processor); a DashPay contact rides
    /// `continueContactPayment`; every other route confirms in
    /// `SendConfirmSheet`.
    ///
    /// Also the contact flow's SECOND and last step: the picker sets the
    /// recipient on the view model and calls this directly, skipping the
    /// address step (there is no address) and the From step (Core is the only
    /// source a contact payment can have).
    func pushExternalSendAmount(viewModel: SendViewModel,
                                onSendCompleted: @escaping () -> Void) {
        let screen = ExternalSendAmountScreen(
            viewModel: viewModel,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onContinueCore: { [weak self] address, amountDuffs in
                self?.continueCore(address: address, amountDuffs: amountDuffs)
            },
            onContinueContact: { [weak self] in
                self?.continueContactPayment(viewModel: viewModel)
            },
            onSendCompleted: onSendCompleted)
        let host = UIHostingController(rootView: screen)
        navigationController?.pushViewController(host, animated: true)
    }

    #if DASHPAY
    /// DashPay pay-to-contact. `WalletSendService.sendToContact` runs the
    /// spend-auth gate and the SDK's single-shot build+sign+broadcast, so the
    /// Send tap was the confirmation and what is left is the success screen —
    /// the same one an address send lands on.
    ///
    /// A failure (or a cancelled PIN prompt) returns nil and leaves the user on
    /// the amount step; the view model carries the message it shows inline.
    fileprivate func continueContactPayment(viewModel: SendViewModel) {
        Task { [weak self] in
            guard let self, let txidWire = await viewModel.sendToContact() else { return }
            self.presentSendSuccess(withTxidWire: txidWire)
        }
    }
    #else
    /// Unreachable here: `contactRecipient` is DashPay-only, so
    /// `ExternalSendAmountScreen`'s contact branch is compiled out of this
    /// target. Asserts rather than pretending a payment happened.
    fileprivate func continueContactPayment(viewModel: SendViewModel) {
        assertionFailure("Contact payment reached in a build without DashPay")
    }
    #endif
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
