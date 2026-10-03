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
        PaymentInFlight.begin()
        guard host == nil, let window = PinPromptPresenter.appWindows().first else { return }
        window.dw_showProgressHUD(withMessage: message)
        host = window
    }

    static func hide() {
        guard owners > 0 else { return }
        owners -= 1
        PaymentInFlight.end()
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

    private func show(modalController: UIViewController) {
        precondition(presentationAnchor != nil)
        presentationAnchor!.topController().present(modalController, animated: true)
    }
}

// MARK: ConfirmPaymentViewControllerDelegate

extension PaymentController: ConfirmPaymentViewControllerDelegate {
    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController) {
        controller.dismiss(animated: true) { [weak self] in
            if let output = self?.paymentOutput {
                self?.paymentProcessor.confirmPaymentOutput(output)
            }
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

    func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        self.paymentOutput = paymentOutput

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
        // outcome; it only needs its way back closed.
        let amountScreenOnScreen = provideAmountViewController?.viewIfLoaded?.window != nil
        if amountScreenOnScreen {
            setAmountScreenLeavable(false)
        }
        let shownByScreen = shownByHandler || amountScreenOnScreen
        guard let anchor = presentationAnchor else { return }
        // Both resolved from the anchor's own stack, not `topController()`: a
        // PIN prompt still finishing its dismissal would otherwise be the one
        // held modal and the one carrying the HUD.
        let stack = anchor.navigationController ?? anchor
        let screen = (stack as? UINavigationController)?.topViewController ?? stack
        sendInProgressExitHold = MainActor.assumeIsolated { ExitHold(on: screen) }
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
