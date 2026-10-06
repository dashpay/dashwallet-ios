//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import DashUIKit
import SwiftUI
import UIKit

typealias PaymentControllerPresentationAnchor = UIViewController

// MARK: - AmountViewController

protocol AmountViewController where Self: BaseAmountViewController { }

// MARK: - PaymentControllerDelegate

@objc
protocol PaymentControllerDelegate: AnyObject {
    /// `txidWire` is the broadcast transaction's wire-order txid
    /// (`Transaction.txHashData` convention) — resolve via `TxDetailModel(txidWire:)`.
    func paymentControllerDidFinishTransaction(_ controller: PaymentController, txidWire: Data)
    func paymentControllerDidCancelTransaction(_ controller: PaymentController)
    func paymentControllerDidFailTransaction(_ controller: PaymentController)
    /// The broadcast got no answer from the network; the send now waits in the
    /// history (`PendingSendOutcomes`). Called once the "Waiting for the
    /// network" notice the controller presents first is gone — closed and
    /// dismissed, or never shown. The delegate leaves the paying flow itself,
    /// a legacy amount step included; for a delegate without this method the
    /// controller pops that step.
    @objc optional func paymentControllerDidSubmitWithUnknownOutcome(_ controller: PaymentController, txidWire: Data)
    /// The broadcast got no answer, told at once — before the notice — for
    /// bookkeeping that must not wait for the user (and is not lost if the
    /// app is killed while the notice is up).
    @objc optional func paymentControllerDidReceiveUnknownOutcome(_ controller: PaymentController, txidWire: Data)
}

// MARK: - PaymentControllerPresentationContextProviding

@objc
protocol PaymentControllerPresentationContextProviding: AnyObject {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor
}

// MARK: - AmountProviding

protocol AmountProviding: ActivityIndicatorPreviewing, ErrorPresentable, PaymentControllerPresentationAnchor { }

// MARK: - WindowProgressHUD

/// A touch-blocking HUD over the whole app window — tab bar, navigation and
/// any sheet included — for a payment waiting on the network on a screen that
/// shows no progress of its own. Counted: each `show` is paired with a `hide`,
/// and the HUD stays up until the last owner hides it.
@MainActor
enum WindowProgressHUD {
    private static weak var host: UIView?
    private static var owners = 0

    static func show(_ message: String) {
        owners += 1
        guard host == nil, let window = PinPromptPresenter.appWindows().first else { return }
        window.dw_showProgressHUD(withMessage: message)
        host = window
    }

    static func hide() {
        guard owners > 0 else { return }
        owners -= 1
        guard owners == 0 else { return }
        host?.dw_hideProgressHUD()
        host = nil
    }

    /// For a CoinJoin sweep started from a row or a popup, which has no
    /// progress state of its own (`WalletSendService.sweepCoinJoin`).
    static func showMovingFunds(_ waiting: Bool) {
        waiting ? show(NSLocalizedString("Moving funds", comment: "CoinJoin")) : hide()
    }
}

// MARK: - PaymentController

final class PaymentController: NSObject {
    @objc weak var delegate: PaymentControllerDelegate?
    @objc weak var presentationContextProvider: PaymentControllerPresentationContextProviding?

    @objc public var locksBalance = false
    /// Called with true when a confirmed send starts waiting for the network,
    /// and with false right before its outcome is shown. Returns whether the
    /// screen shows that progress itself; when it does not (or no handler is
    /// set), a "Sending" HUD covers the window for the wait.
    @objc var sendInProgressHandler: ((Bool) -> Bool)?
    /// The active wallet's payment to an address still waiting for the
    /// network (`PendingSendOutcomes.waitingPayment(to:)`); tests replace it.
    var waitingPayment: @MainActor (String) -> PendingSendOutcomes.Entry? = {
        PendingSendOutcomes.shared.waitingPayment(to: $0)
    }

    private var paymentProcessor: DWPaymentProcessor
    private var fiatCurrency: String = App.fiatCurrency
    private weak var paymentOutput: DWPaymentOutput?
    private weak var confirmViewController: ConfirmPaymentViewController?
    private weak var provideAmountViewController: AmountProviding?
    /// The hold on the paying screen's ways out while a send is in progress.
    private var sendInProgressExitHold: ExitHold?
    /// This controller put up the window HUD for the send in progress.
    private var showsWindowProgressHUD = false

    static func shouldReenableSending(after error: NSError) -> Bool {
        !WalletSendService.isBroadcastUnknownError(error)
    }

    override init() {
        paymentProcessor = DWPaymentProcessor()

        super.init()

        paymentProcessor.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Released mid-send, the NO callback never arrives (the processor's
        // delegate is weak): give back what this controller holds.
        let exitHold = sendInProgressExitHold
        let ownsWindowHUD = showsWindowProgressHUD
        Task { @MainActor in
            exitHold?.release()
            if ownsWindowHUD { WindowProgressHUD.hide() }
        }
    }

    @objc
    public func performPayment(with input: DWPaymentInput) {
        paymentProcessor.reset()
        paymentProcessor.processPaymentInput(input)
    }
}

extension PaymentController {
    var presentationAnchor: PaymentControllerPresentationAnchor? {
        provideAmountViewController ?? presentationContextProvider?.presentationAnchorForPaymentController(self)
    }

    private func showAlert(with title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
        alert.addAction(okAction)
        show(modalController: alert)
    }

    /// Ends a payment that will not be sent and says so: the user may have
    /// confirmed it already.
    private func endWithoutSending(reason: String) {
        DWLogger.log("PaymentController: \(reason)")
        provideAmountViewController?.hideActivityIndicator()
        if presentationAnchor != nil {
            showAlert(with: NSLocalizedString("Couldn't make payment", comment: ""), message: nil)
        }
        delegate?.paymentControllerDidFailTransaction(self)
    }

    private func show(modalController: UIViewController) {
        precondition(presentationAnchor != nil)
        presentationAnchor!.topController().present(modalController, animated: true)
    }
}

// MARK: ConfirmPaymentViewControllerDelegate

extension PaymentController: ConfirmPaymentViewControllerDelegate {
    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            guard let output = self.paymentOutput else {
                self.endWithoutSending(reason: "the confirmed payment had no output left to send")
                return
            }
            self.paymentProcessor.confirmPaymentOutput(output)
        }
    }

    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController) {
        provideAmountViewController?.hideActivityIndicator()
        delegate?.paymentControllerDidCancelTransaction(self)
    }
}

// MARK: DWPaymentProcessorDelegate

extension PaymentController: DWPaymentProcessorDelegate {
    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String, amount: UInt64) {
        provideAmountViewController = nil
        let vc = ProvideAmountViewController(address: sendingDestination, amount: amount)
        vc.locksBalance = locksBalance
        vc.delegate = self
        vc.hidesBottomBarWhenPushed = true
        vc.definesPresentationContext = true
        // vc.demoMode = self.demoMode; //TODO: demoMode
        presentationAnchor!.navigationController?.pushViewController(vc, animated: true)
        provideAmountViewController = vc
    }

    /// A payment to an address that still has one waiting for the network is
    /// not made: the earlier one may yet arrive, and the recipient would get
    /// both. The user is told to wait, and OK returns to the paying screen —
    /// before the PIN prompt and the build, nothing is built or signed. Not
    /// asked again while the confirm sheet is up; other addresses are not
    /// interrupted.
    func paymentProcessor(_ processor: DWPaymentProcessor, shouldPayAddress address: String, completion: @escaping (Bool) -> Void) {
        guard confirmViewController == nil,
              let waiting = MainActor.assumeIsolated({ waitingPayment(address) }) else {
            completion(true)
            return
        }
        refuseRepeating(waiting) { completion(false) }
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        self.paymentOutput = paymentOutput
        presentConfirm(for: paymentOutput)
    }

    /// Tells the user the previous payment to this address must be confirmed
    /// first; `done` runs once the notice is gone (or could not be shown).
    private func refuseRepeating(_ waiting: PendingSendOutcomes.Entry, done: @escaping () -> Void) {
        let message = String(
            format: NSLocalizedString(
                "Your previous payment to this address (%1$@, %2$@) is still being processed by the network. Wait until it is confirmed before paying this address again.",
                comment: "Send: a payment to an address whose earlier payment is still waiting for the network is not made; %1$@ is the earlier payment's amount, %2$@ when it was sent"),
            waiting.amount.formattedDashAmount,
            "\(DWDateFormatter.sharedInstance.shortStringFromDate(waiting.sentAt)) \(DWDateFormatter.sharedInstance.timeOnly(from: waiting.sentAt))")
        guard let presenter = presentationAnchor?.topController() else {
            DWLogger.log("PaymentController: no screen to show the repeat-payment notice on; not sending")
            done()
            return
        }
        Self.presentDialog(
            on: presenter,
            heading: NSLocalizedString("Previous payment still in progress", comment: "Send: a payment to an address whose earlier payment is still waiting for the network is not made"),
            message: message,
            buttonText: NSLocalizedString("OK", comment: ""),
            log: "the repeat-payment notice",
            onClosed: done)
    }

    private func presentConfirm(for paymentOutput: DWPaymentOutput) {
        if let vc = confirmViewController {
            vc.update(with: paymentOutput)
        } else {
            let vc = ConfirmPaymentViewController(dataSource: paymentOutput, fiatCurrency: fiatCurrency)
            vc.delegate = self

            // TODO: demo mode

            presentationAnchor?.topController().present(vc, animated: true)
            confirmViewController = vc
        }
    }

    func paymentProcessorDidCancelTransactionSigning(_ processor: DWPaymentProcessor) {
        provideAmountViewController?.hideActivityIndicator()
        delegate?.paymentControllerDidCancelTransaction(self)
        confirmViewController?.isSendingEnabled = true
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Error?, title: String?, message: String?) {
        // Pre-existing behavior kept: nil-error failures (invalid-address rejections)
        // stay silent here. The DashSync DSErrorDomain special-case is gone — live
        // errors carry WalletSendService / SDK / BIP70 domains.
        // The amount screen's submission ends either way, or a silent failure
        // would leave it locked.
        provideAmountViewController?.hideActivityIndicator()
        // Told after the alert is up, silent failures included: a screen that
        // keeps its input off until its payment ends would otherwise stay off.
        defer { delegate?.paymentControllerDidFailTransaction(self) }
        guard let error else {
            return
        }

        presentationAnchor?.topController().view.dw_hideProgressHUD()

        confirmViewController?.isSendingEnabled =
            Self.shouldReenableSending(after: error as NSError)

        showAlert(with: title, message: message)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSendWithTxidWire txidWire: Data) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()

        let finishBlock = {
            // The pop is for the LEGACY amount screen, which the redesigned
            // send flow never pushes: it collects the amount on its own step
            // and hands the processor an address and a value together. Telling
            // the delegate the send finished is not conditional on that screen
            // — it used to sit inside this check, so a flow without one sent
            // successfully and then showed nothing at all.
            if let vc = self.presentationAnchor?.navigationController?.topViewController as? AmountProviding {
                vc.navigationController?.popViewController(animated: true)
            }

            DispatchQueue.main.async {
                self.delegate?.paymentControllerDidFinishTransaction(self, txidWire: txidWire)
            }
        }

        guard let vc = confirmViewController else {
            finishBlock()
            return
        }

        vc.dismiss(animated: true) {
            finishBlock()
        }
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSendWithUnknownOutcomeTxidWire txidWire: Data) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()
        delegate?.paymentControllerDidReceiveUnknownOutcome?(self, txidWire: txidWire)

        // The notice first; the paying screen goes on once it is gone. Presented
        // in the same turn as the outcome's report when no confirm sheet is up,
        // so the router sees a presented modal from the routing hold's end on;
        // after a confirm sheet, once that sheet is gone. The legacy amount
        // screen keeps its input off until then: a hardware keyboard under the
        // notice would otherwise still edit it.
        let showNotice = {
            let closed = { [weak self] in
                guard let self else { return }
                if let delegate = self.delegate,
                   (delegate as? NSObject)?.responds(
                       to: #selector(PaymentControllerDelegate.paymentControllerDidSubmitWithUnknownOutcome(_:txidWire:))) == true {
                    // The paying screen leaves the whole flow itself (one
                    // navigation change, not a pop racing its own).
                    delegate.paymentControllerDidSubmitWithUnknownOutcome?(self, txidWire: txidWire)
                } else if let amountScreen = self.presentationAnchor?.navigationController?.topViewController as? AmountProviding {
                    // As after a sent payment: the amount step is done.
                    amountScreen.navigationController?.popViewController(animated: true)
                } else {
                    self.provideAmountViewController?.hideActivityIndicator()
                }
            }
            guard let top = self.presentationAnchor?.topController() else {
                DWLogger.log("PaymentController: no screen to show the unknown-outcome notice on")
                closed()
                return
            }
            Self.showUnknownOutcomeNotice(on: top, onClosed: closed)
        }
        guard let vc = confirmViewController else {
            showNotice()
            return
        }
        vc.dismiss(animated: true) { showNotice() }
    }

    /// The "Waiting for the network" notice for a send whose broadcast got no
    /// answer, presented on `viewController`. `onClosed` runs exactly once,
    /// when the notice is gone (see `presentDialog`) — a paying screen waiting
    /// for it is never stranded.
    static func showUnknownOutcomeNotice(on viewController: UIViewController, onClosed: (() -> Void)? = nil) {
        presentDialog(
            on: viewController,
            heading: NSLocalizedString("Waiting for the network", comment: "Sent transaction whose broadcast got no answer from the network yet"),
            message: unknownOutcomeMessage,
            buttonText: NSLocalizedString("OK", comment: ""),
            log: "the unknown-outcome notice") { onClosed?() }
    }

    /// A warning dialog with one button whose close is reported exactly once,
    /// from its own host: `onClosed` runs once the dialog's dismissal has
    /// finished (so it can present or dismiss in turn), when it was torn down
    /// any other way, or right away when UIKit did not present it at all. A
    /// flow waiting on it always goes on.
    static func presentDialog(
        on viewController: UIViewController,
        heading: String,
        message: String,
        buttonText: String,
        log: String,
        onClosed: @escaping () -> Void
    ) {
        var closed = false
        let close = {
            guard !closed else { return }
            closed = true
            onClosed()
        }
        let host = DialogHostingController(rootView: ModalDialog(
            style: .warning,
            icon: .system("exclamationmark.triangle"),
            heading: heading,
            textBlock1: message,
            positiveButtonText: buttonText,
            positiveButtonAction: {}))
        var tapped = false
        host.rootView.positiveButtonAction = { [weak host] in
            // A second tap during the dismissal would reach the presenter.
            guard !tapped else { return }
            tapped = true
            host?.dismiss(animated: true)
        }
        host.onDisappear = close
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = UIColor(Color.dash.backgroundOverlay)
        viewController.present(host, animated: true)
        if host.presentingViewController == nil {
            DWLogger.log("PaymentController: \(log) could not be shown")
            close()
        }
    }

    /// A dialog's host: reports when it has left the screen — dismissed
    /// itself, or freed when a controller below it was dismissed.
    private final class DialogHostingController: UIHostingController<ModalDialog> {
        /// Set once on the main actor before presentation; read again only
        /// by `deinit`, after every other reference is gone.
        nonisolated(unsafe) var onDisappear: (() -> Void)?

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // Gone, not merely covered by something presented over it.
            guard isBeingDismissed || presentingViewController == nil else { return }
            onDisappear?()
        }

        deinit {
            // `onDisappear` reports once; this catches a teardown that left no
            // trace in `viewDidDisappear`.
            let report = onDisappear
            DispatchQueue.main.async { report?() }
        }
    }

    static let unknownOutcomeMessage = NSLocalizedString(
        "The network hasn't confirmed this payment yet. It's in your history as \"Waiting for the network\" — don't send it again.",
        comment: "Send: the broadcast got no answer; the payment is followed in the history")

    /// While the send waits, its screen must stay: swiped away, the outcome
    /// would have nowhere to show, and a live screen would take a second tap —
    /// a second payment. A screen that shows the progress itself says so
    /// through `sendInProgressHandler`; otherwise a "Sending" HUD covers the
    /// whole window and blocks touches for the wait.
    func paymentProcessor(_ processor: DWPaymentProcessor, broadcastInProgress inProgress: Bool) {
        let shownByHandler = sendInProgressHandler?(inProgress) ?? false
        guard inProgress else {
            MainActor.assumeIsolated {
                sendInProgressExitHold?.release()
                sendInProgressExitHold = nil
            }
            if showsWindowProgressHUD {
                MainActor.assumeIsolated { WindowProgressHUD.hide() }
                showsWindowProgressHUD = false
            }
            setAmountScreenLeavable(true)
            return
        }
        // The legacy amount screen keeps its button spinner from the tap to the
        // outcome; it only needs its way back closed. A retry from the confirm
        // sheet after a failure, which ended the first submission, starts it
        // again so the amount is locked for this broadcast too.
        let amountScreenOnScreen = provideAmountViewController?.viewIfLoaded?.window != nil
        if amountScreenOnScreen {
            setAmountScreenLeavable(false)
        }
        (provideAmountViewController as? BaseAmountViewController)?.beginSubmission()
        let shownByScreen = shownByHandler || amountScreenOnScreen
        guard let anchor = presentationAnchor else { return }
        // Both resolved from the anchor's own stack, not `topController()`: a
        // PIN prompt still finishing its dismissal would otherwise be the one
        // held modal and the one carrying the HUD.
        let stack = anchor.navigationController ?? anchor
        let screen = (stack as? UINavigationController)?.topViewController ?? stack
        // Routing is held by the payment processor for the wait; this hold is
        // for the exits only.
        sendInProgressExitHold = MainActor.assumeIsolated { ExitHold(on: screen, ownsRouting: false) }
        if !shownByScreen {
            // On the window, not the screen: a screen inside a tab leaves the
            // tab bar — and its Send button — live around a screen-sized HUD.
            MainActor.assumeIsolated { WindowProgressHUD.show(NSLocalizedString("Sending", comment: "")) }
            showsWindowProgressHUD = true
        }
    }

    /// Back of the legacy amount screen, a navigation-bar button, closed while
    /// its send waits so the outcome keeps its screen. The edge swipe is held
    /// with the other ways out (`ExitHold`).
    private func setAmountScreenLeavable(_ leavable: Bool) {
        provideAmountViewController?.navigationController?.navigationBar.isUserInteractionEnabled = leavable
    }

    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        presentationAnchor?.topController().view.dw_hideProgressHUD()
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        presentationAnchor?.topController().view.dw_showProgressHUD(withMessage: message)
    }
}

// MARK: ProvideAmountViewControllerDelegate

extension PaymentController: ProvideAmountViewControllerDelegate {
    func provideAmountViewControllerDidInput(amount: UInt64, selectedCurrency: String) {
        fiatCurrency = selectedCurrency
        paymentProcessor.provideAmount(amount)
    }
}
