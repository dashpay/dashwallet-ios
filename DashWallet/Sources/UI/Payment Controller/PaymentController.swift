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

// MARK: - PaymentController

/// One payment this controller runs: its own processor; its link
/// settlement and abandonment live in `LinkOperationSequence` under its
/// token. A controller serves a screen for its lifetime, so payment B can
/// start while A's preparation (a BIP70 fetch, a BIP73 hop) is still alive;
/// A's processor keeps calling back, and only the operation the sequence
/// admits may act on a callback.
private final class PaymentOperation {
    let token: LinkOperationSequence.Token
    let processor: DWPaymentProcessor

    init(token: LinkOperationSequence.Token, processor: DWPaymentProcessor) {
        self.token = token
        self.processor = processor
    }
}

final class PaymentController: NSObject {
    @objc weak var delegate: PaymentControllerDelegate?
    @objc weak var presentationContextProvider: PaymentControllerPresentationContextProviding?

    @objc public var locksBalance = false

    private let operations = LinkOperationSequence()
    private var operation: PaymentOperation?
    private var fiatCurrency: String = App.fiatCurrency
    private weak var paymentOutput: DWPaymentOutput?
    private weak var confirmViewController: ConfirmPaymentViewController?
    private weak var provideAmountViewController: AmountProviding?

    static func shouldReenableSending(after error: NSError) -> Bool {
        !WalletSendService.isBroadcastUnknownError(error)
    }

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func performPayment(with input: DWPaymentInput) {
        performPayment(with: input, presentationSettled: nil, isAbandoned: nil)
    }

    /// `performPayment(with:)` for a deep link: `presentationSettled` runs
    /// once — when the first screen this payment shows has finished
    /// presenting (the amount step, the confirmation, an error alert), or
    /// when preparation ends without one (cancelled, or a failure with no
    /// message). The link queue hands the next link over only then.
    /// `isAbandoned` is asked right before a screen would be presented: a
    /// payment the queue has given up presents nothing.
    @objc(performPaymentWith:presentationSettled:isAbandoned:)
    public func performPayment(with input: DWPaymentInput, presentationSettled: @escaping () -> Void, isAbandoned: @escaping () -> Bool) {
        performPayment(with: input, presentationSettled: Optional(presentationSettled), isAbandoned: Optional(isAbandoned))
    }

    /// Every payment is a new operation with its own processor: the one
    /// before it is obsolete from here on, its processor's callbacks are
    /// refused by `admitted(_:)` and its link (if any) is settled, since it
    /// will show nothing.
    ///
    /// The new operation is current before the previous one's link is
    /// settled, and that settlement is delivered on the next main-queue
    /// turn: settling a link hands the queue's next link over, which can
    /// start another payment on this controller, and that must not run
    /// inside this call (it would install its operation and push its
    /// amount step, and this call would then overwrite both). Should
    /// anything below re-enter all the same, the token is no longer
    /// admitted and this call stops; the payment that replaced it has
    /// settled it.
    private func performPayment(with input: DWPaymentInput, presentationSettled: (() -> Void)?, isAbandoned: (() -> Bool)?) {
        // A confirmed send keeps this controller until it reports its
        // outcome: replacing it would drop that outcome, the
        // unknown-broadcast warning included. The newcomer is refused with an
        // alert and its link settles once the alert is on screen.
        guard !operations.isCommitted else {
            DWLogger.log("PAY a payment arrived while a confirmed send is in flight; refused")
            showRefusal(for: operations.refuse(settled: presentationSettled))
            return
        }
        let token = operations.begin(settled: presentationSettled, isAbandoned: isAbandoned)
        guard operations.admits(token) else {
            DWLogger.log("PAY a payment started while this one was being installed; this one is dropped")
            return
        }
        // The previous operation's screens are not this one's: the link
        // queue dismissed what was presented before handing this link over,
        // a confirmation left behind must never be updated with this
        // payment, and an amount step left on the navigation stack — it was
        // pushed, not presented — must not sit beneath this payment's screen
        // where Back would reach it, so it is taken out of the stack and
        // unhooked from this controller.
        confirmViewController = nil
        removeSupersededAmountStep()
        paymentOutput = nil
        guard operations.admits(token) else {
            DWLogger.log("PAY a payment started while this one was being installed; this one is dropped")
            return
        }
        let processor = DWPaymentProcessor()
        processor.delegate = self
        operation = PaymentOperation(token: token, processor: processor)
        processor.processPaymentInput(input)
    }

    /// Whether a send the user confirmed has not reported its outcome yet;
    /// a payment started meanwhile is refused.
    @objc public var hasPaymentInFlight: Bool {
        operations.isCommitted
    }

    /// Takes the previous operation's amount step out of its navigation
    /// stack (without animation: the new operation is about to push or
    /// present) and detaches it, so it can neither be reached by Back nor
    /// hand this controller an amount.
    private func removeSupersededAmountStep() {
        guard let stale = provideAmountViewController else { return }
        provideAmountViewController = nil
        (stale as? ProvideAmountViewController)?.delegate = nil
        guard let screen = stale as? UIViewController, let navigation = screen.navigationController else { return }
        let stack = navigation.viewControllers
        let remaining = stack.filter { $0 !== screen }
        guard remaining.count < stack.count else { return }
        navigation.setViewControllers(remaining, animated: false)
        DWLogger.log("PAY removed the previous payment's amount step from the navigation stack (\(stack.count) → \(remaining.count))")
    }

    /// The current operation when `processor` is its processor; nil — and
    /// a log line — for a callback from an operation this controller has
    /// moved past, which then mutates nothing and presents nothing.
    private func admitted(_ processor: DWPaymentProcessor, _ callback: StaticString = #function) -> PaymentOperation? {
        guard let operation, operation.processor === processor, operations.admits(operation.token) else {
            DWLogger.log("PAY a callback (\(callback)) from a payment this controller has moved past; ignored")
            return nil
        }
        return operation
    }

    /// Settles `token`'s link — that operation's own, never whichever
    /// operation is current by the time a presentation completes. Once per
    /// operation; later calls are no-ops.
    private func settlePresentation(of token: LinkOperationSequence.Token) {
        operations.settle(token)
    }

    /// True — and the payment is dropped, logged and settled — when the
    /// link queue has moved on without this payment.
    private func dropIfAbandoned(_ operation: PaymentOperation, _ screen: String) -> Bool {
        guard operations.isAbandoned(operation.token) else { return false }
        DWLogger.log("PAY the link queue gave this payment up before its \(screen) was ready; presenting nothing")
        operation.processor.reset()
        operations.finishCommitted(operation.token)
        settlePresentation(of: operation.token)
        return true
    }

    /// `settlePresentation(of:)` once `transition` (a push's coordinator)
    /// has finished, or on the next run-loop turn when nothing is animating.
    private func settlePresentation(of token: LinkOperationSequence.Token, after transition: UIViewControllerTransitionCoordinator?) {
        guard operations.awaitsSettlement(token) else { return }
        if let transition {
            transition.animate(alongsideTransition: nil) { [weak self] _ in self?.settlePresentation(of: token) }
        } else {
            DispatchQueue.main.async { [weak self] in self?.settlePresentation(of: token) }
        }
    }
}

extension PaymentController {
    var presentationAnchor: PaymentControllerPresentationAnchor? {
        provideAmountViewController ?? presentationContextProvider?.presentationAnchorForPaymentController(self)
    }

    private func showAlert(with title: String?, message: String?, for token: LinkOperationSequence.Token) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
        alert.addAction(okAction)
        show(modalController: alert, for: token)
    }

    /// The refusal of a payment that arrived while a confirmed send is in
    /// flight. The confirmation may still be animating away (the send is
    /// committed at the tap, before its dismissal ends), and a controller
    /// in transition can refuse the alert or take it down with it: the top
    /// is resolved again once its transition has ended. With nothing on
    /// screen to present from, the link settles without an alert rather
    /// than waiting for the queue's watchdog.
    private func showRefusal(for token: LinkOperationSequence.Token, attempt: Int = 0) {
        let top = presentationAnchor?.topController()
        let decision = RefusalPresentation.decide(
            topInTransition: top.map { $0.isInTransition || $0.transitionCoordinator != nil } ?? false,
            topInWindow: top?.viewIfLoaded?.window != nil,
            attempt: attempt)
        switch decision {
        case .wait:
            let retry: () -> Void = { [weak self] in self?.showRefusal(for: token, attempt: attempt + 1) }
            if let coordinator = top?.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in DispatchQueue.main.async(execute: retry) }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + RefusalPresentation.poll, execute: retry)
            }
        case .present:
            showAlert(with: nil,
                      message: NSLocalizedString("A payment is still being sent. Open the link again once it finishes.",
                                                 comment: "Payment: a payment link arrived while a send is in flight"),
                      for: token)
        case .settleWithoutAlert:
            DWLogger.log("PAY nothing on screen to present the refusal from; settling the refused link")
            settlePresentation(of: token)
        }
    }

    private func show(modalController: UIViewController, for token: LinkOperationSequence.Token) {
        precondition(presentationAnchor != nil)
        presentationAnchor!.topController().present(modalController, animated: true) { [weak self] in
            self?.settlePresentation(of: token)
        }
    }
}

// MARK: ConfirmPaymentViewControllerDelegate

extension PaymentController: ConfirmPaymentViewControllerDelegate {
    /// From here on the send is committed: no other payment may replace
    /// this one until its processor reports success, failure or a
    /// cancelled authentication.
    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController) {
        if let operation, paymentOutput != nil {
            operations.commit(operation.token)
        }
        controller.dismiss(animated: true) { [weak self] in
            if let output = self?.paymentOutput {
                self?.operation?.processor.confirmPaymentOutput(output)
            }
        }
    }

    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController) {
        if let operation {
            operations.finishCommitted(operation.token)
        }
        provideAmountViewController?.hideActivityIndicator()
        delegate?.paymentControllerDidCancelTransaction(self)
    }
}

// MARK: DWPaymentProcessorDelegate

extension PaymentController: DWPaymentProcessorDelegate {
    func paymentProcessor(_ processor: DWPaymentProcessor, requestAmountWithDestination sendingDestination: String, amount: UInt64) {
        guard let operation = admitted(processor) else { return }
        // Back in preparation: whatever was confirmed was not sent.
        operations.finishCommitted(operation.token)
        provideAmountViewController = nil
        if dropIfAbandoned(operation, "amount step") { return }
        let vc = ProvideAmountViewController(address: sendingDestination, amount: amount)
        vc.locksBalance = locksBalance
        vc.delegate = self
        vc.hidesBottomBarWhenPushed = true
        vc.definesPresentationContext = true
        // vc.demoMode = self.demoMode; //TODO: demoMode
        let navigation = presentationAnchor!.navigationController
        navigation?.pushViewController(vc, animated: true)
        provideAmountViewController = vc
        operations.bind(ObjectIdentifier(vc), to: operation.token)
        settlePresentation(of: operation.token, after: navigation?.transitionCoordinator)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, confirmPaymentOutput paymentOutput: DWPaymentOutput) {
        guard let operation = admitted(processor) else { return }
        // A new confirmation is asked for: nothing was sent yet, and the user
        // decides again.
        operations.finishCommitted(operation.token)
        if dropIfAbandoned(operation, "confirmation") { return }
        self.paymentOutput = paymentOutput

        if let vc = confirmViewController {
            vc.update(with: paymentOutput)
            settlePresentation(of: operation.token)
        } else {
            let vc = ConfirmPaymentViewController(dataSource: paymentOutput, fiatCurrency: fiatCurrency)
            vc.delegate = self

            // TODO: demo mode

            let token = operation.token
            presentationAnchor?.topController().present(vc, animated: true) { [weak self] in
                self?.settlePresentation(of: token)
            }
            confirmViewController = vc
        }
    }

    func paymentProcessorDidCancelTransactionSigning(_ processor: DWPaymentProcessor) {
        guard let operation = admitted(processor) else { return }
        operations.finishCommitted(operation.token)
        provideAmountViewController?.hideActivityIndicator()
        delegate?.paymentControllerDidCancelTransaction(self)
        confirmViewController?.isSendingEnabled = true
        settlePresentation(of: operation.token)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didFailWithError error: Error?, title: String?, message: String?) {
        guard let operation = admitted(processor) else { return }
        operations.finishCommitted(operation.token)
        // Pre-existing behavior kept: nil-error failures (invalid-address rejections)
        // stay silent here. The DashSync DSErrorDomain special-case is gone — live
        // errors carry WalletSendService / SDK / BIP70 domains.
        guard let error else {
            settlePresentation(of: operation.token)
            return
        }

        presentationAnchor?.topController().view.dw_hideProgressHUD()
        provideAmountViewController?.hideActivityIndicator()
        if dropIfAbandoned(operation, "error alert") { return }

        confirmViewController?.isSendingEnabled =
            Self.shouldReenableSending(after: error as NSError)

        showAlert(with: title, message: message, for: operation.token)
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, didSendWithTxidWire txidWire: Data) {
        guard let operation = admitted(processor) else { return }
        operations.finishCommitted(operation.token)
        presentationAnchor?.topController().view.dw_hideProgressHUD()
        settlePresentation(of: operation.token)

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

    func paymentInputProcessorHideProgressHUD(_ processor: DWPaymentProcessor) {
        guard admitted(processor) != nil else { return }
        presentationAnchor?.topController().view.dw_hideProgressHUD()
    }

    func paymentProcessor(_ processor: DWPaymentProcessor, showProgressHUDWithMessage message: String?) {
        guard admitted(processor) != nil else { return }
        presentationAnchor?.topController().view.dw_showProgressHUD(withMessage: message)
    }
}

// MARK: ProvideAmountViewControllerDelegate

extension PaymentController: ProvideAmountViewControllerDelegate {
    /// Only the current operation's own amount step may feed it an amount:
    /// a step left over from an earlier payment is refused, whichever
    /// processor is current.
    func provideAmountViewController(_ controller: ProvideAmountViewController, didInput amount: UInt64, selectedCurrency: String) {
        guard let operation, operations.admits(screen: ObjectIdentifier(controller)) else {
            DWLogger.log("PAY an amount from a screen that is not the current payment's; ignored")
            controller.hideActivityIndicator()
            return
        }
        fiatCurrency = selectedCurrency
        operation.processor.provideAmount(amount)
    }
}

/// Where the refusal of a payment link goes, given the top of the hierarchy
/// it would be presented from. Separated so the decision is testable
/// without a window.
enum RefusalPresentation {
    enum Decision: Equatable {
        /// The top is still being presented or dismissed: wait and resolve
        /// it again.
        case wait
        case present
        /// Nothing in a window to present from.
        case settleWithoutAlert
    }

    /// How often, and how long apart, the refusal waits for a transition
    /// before presenting anyway (about 2 s in all).
    static let waits = 20
    static let poll: TimeInterval = 0.1

    static func decide(topInTransition: Bool, topInWindow: Bool, attempt: Int) -> Decision {
        if topInTransition && attempt < waits {
            return .wait
        }
        return topInWindow ? .present : .settleWithoutAlert
    }
}
