//
//  PaymentsLandingHostingController.swift
//  DashWallet
//

import Combine
import SwiftUI
import UIKit

@objc(DWPaymentsLandingHostingController)
final class PaymentsLandingHostingController: DWBasePayViewController {

    private let viewModel: PaymentsLandingViewModel
    /// The Internal tab's embedded transfer form. Un-pinned (free From/To
    /// pickers) on the full landing; the balance-row receive sheet pins the
    /// destination (`transferReceivePinned`), the send sheet pins the source
    /// (`transferSendFrom`).
    private let embeddedTransferViewModel: InternalTransferViewModel
    private let transferReceivePinned: Bool
    /// The Send tab's form. Pinned to the tapped balance as source for the
    /// balance-row send sheet (`transferSendFrom` then also pins the
    /// Internal tab's From card); un-pinned on the full landing.
    private let embeddedSendViewModel: SendViewModel
    private let transferSendFrom: ChainNetwork?
    private lazy var hostingController: UIHostingController<PaymentsLandingScreen> = {
        let screen = PaymentsLandingScreen(
            viewModel: viewModel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onDone: { [weak self] in self?.finishReceiving() },
            onCopyAddress: { [weak self] in self?.copyCurrentAddress() },
            onShareAddress: { [weak self] in self?.shareCurrentAddress() },
            onSpecifyAmount: { [weak self] in self?.pushSpecifyAmount() },
            onViewTransaction: { [weak self] txid in self?.showTransaction(txid: txid) },
            onScanQR: { [weak self] in self?.performScanQRCodeAction() },
            embeddedTransferViewModel: embeddedTransferViewModel,
            onTransferCompleted: { [weak self] in self?.dismiss(animated: true) },
            transferSendFrom: transferSendFrom,
            transferReceivePinned: transferReceivePinned,
            embeddedSendViewModel: embeddedSendViewModel,
            onSendContinue: { [weak self] in
                guard let self else { return }
                self.pushExternalSendSource(
                    viewModel: self.embeddedSendViewModel,
                    onSendCompleted: { [weak self] in self?.dismiss(animated: true) })
            },
            onSendToAddress: { [weak self] in self?.pushSendToAddress() },
            onSendToUsername: { [weak self] in self?.showContactBook() },
            onSwapToCrypto: { [weak self] in self?.presentDashDEX() },
            onCloseLanding: { [weak self] in self?.leaveLanding() },
            showsHeader: showsHeader)
        return UIHostingController(rootView: screen)
    }()

    /// False for the balance-row receive sheet (grabber + hero selector
    /// only); the full-screen landing keeps its X + title row.
    private let showsHeader: Bool

    private static let shieldedBalanceTimingShownKey = "DWShieldedBalanceTimingShown"

    private var cancellables = Set<AnyCancellable>()
    /// Set while the receive flow pushes one of its OWN steps.
    ///
    /// Specify Amount is not somewhere else — it is the next screen of the same
    /// receive, and the address it is naming an amount for is the one the
    /// session was armed on. Without this the landing's `viewWillDisappear`
    /// suspends watching the moment that screen is pushed, so nothing is
    /// detected while the user is on the very screen they are handing over.
    private var isPushingReceiveStep = false
    /// The specify-amount sheet while it is up, so a receipt can dismiss it.
    private weak var requestAmountController: RequestAmountHostingController?
    /// Kept apart from `cancellables`: these live exactly as long as that sheet
    /// does, and are dropped with it rather than for the screen's lifetime.
    private var requestAmountObservers = Set<AnyCancellable>()
    /// Live for as long as a receive step is pushed — the sheet is optional
    /// within that, and the return has to happen with or without it.
    private var receiveStepObservers = Set<AnyCancellable>()
    /// The Internal tab was activated before the landing finished appearing
    /// (e.g. it is the initial tab) — present the timing sheet from
    /// `viewDidAppear` instead of against a view that isn't on screen yet.
    private var timingSheetPendingAppearance = false

    @objc
    init(activeTab: Int) {
        let resolved = PaymentsLandingTab.allCases.first { $0.rawValue == Self.tabRawValue(for: activeTab) }
            ?? .send
        self.viewModel = PaymentsLandingViewModel(activeTab: resolved)
        // The full landing's Internal tab is the transfer form itself,
        // un-pinned: free From and To pickers.
        self.embeddedTransferViewModel = InternalTransferViewModel()
        self.transferReceivePinned = false
        // The full landing's Send tab is the send form itself (un-pinned:
        // full From picker) — same form the balance-row sheet embeds.
        self.embeddedSendViewModel = SendViewModel()
        self.transferSendFrom = nil
        self.showsHeader = true
        super.init(nibName: nil, bundle: nil)
    }

    /// `receiveNetwork` preselects the Receive tab's Core/Platform/Shielded
    /// toggle — the balance-row receive arrows open the landing on the
    /// balance the user tapped. `visibleTabs` narrows the hero selector
    /// (the receive/send sheets show two tabs), and `embedInternalTransfer`
    /// makes the Internal tab the transfer form itself rather than the
    /// action-row list.
    ///
    /// `sendNetwork` builds the balance-row SEND sheet: the Send tab's form
    /// is pinned to that balance as source, and the embedded transfer form
    /// pins it as the From card (destination picked on the To rows). Without
    /// it, the Send tab still embeds the form, just un-pinned (full From
    /// picker).
    init(activeTab: PaymentsLandingTab,
         receiveNetwork: ChainNetwork = .core,
         visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
         embedInternalTransfer: Bool = false,
         sendNetwork: ChainNetwork? = nil,
         showsHeader: Bool = true,
         allowsTransactionDetails: Bool = true) {
        self.viewModel = PaymentsLandingViewModel(
            activeTab: activeTab,
            network: receiveNetwork,
            visibleTabs: visibleTabs,
            allowsTransactionDetails: allowsTransactionDetails)
        self.showsHeader = showsHeader
        self.embeddedSendViewModel = SendViewModel(pinnedSource: sendNetwork)
        self.transferSendFrom = sendNetwork
        let transferViewModel = InternalTransferViewModel()
        if let sendNetwork {
            transferViewModel.applySendRoute(from: sendNetwork)
            self.transferReceivePinned = false
        } else if embedInternalTransfer {
            transferViewModel.applyReceiveRoute(into: receiveNetwork)
            self.transferReceivePinned = true
        } else {
            // Free-form landing: no pinned endpoint.
            self.transferReceivePinned = false
        }
        self.embeddedTransferViewModel = transferViewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The lock screen's Quick Receive sheet: the landing narrowed to the
    /// Receive tab, whose Transparent/Platform/Shielded toggle works
    /// pre-auth (address derivation needs no unlock — same posture as the
    /// legacy quick-receive screen this replaces). Receive-only on
    /// purpose: no send/transfer surface while locked.
    @objc static func quickReceiveController() -> UIViewController {
        let controller = PaymentsLandingHostingController(
            activeTab: .receive,
            visibleTabs: [.receive],
            showsHeader: false,
            allowsTransactionDetails: false)
        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.isNavigationBarHidden = true
        navigationController.isModalInPresentation = false
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }

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

        // Receive sheet: keep the pinned transfer route in lockstep with
        // the receive toggle, so the fixed To card and the executed
        // transfer can never disagree. (`$network` republishes the current
        // value on subscription, covering the initial state too.)
        if transferReceivePinned {
            viewModel.$network
                .receive(on: RunLoop.main)
                .sink { [weak self] network in
                    self?.embeddedTransferViewModel.applyReceiveRoute(into: network)
                }
                .store(in: &cancellables)
        }

        // First-time transfer-timing education, free-form landing only —
        // the balance-row sheets never showed it and keep that behavior.
        if transferSendFrom == nil && !transferReceivePinned {
            viewModel.$activeTab
                .receive(on: RunLoop.main)
                .sink { [weak self] tab in
                    guard let self, tab == .internalTransfer else { return }
                    if self.view.window == nil {
                        self.timingSheetPendingAppearance = true
                    } else {
                        self.presentTransferTimingSheetIfNeeded()
                    }
                }
                .store(in: &cancellables)

            // The endpoints move after the tab opens — the form starts on one
            // route and the user picks another — and the sheet is gated on a
            // shielded end. Watching the tab alone would mean anyone who
            // arrived on a transparent route never saw it at all.
            //
            // `objectWillChange` fires before the value lands, so the check is
            // deferred a turn to read the new endpoints. It is cheap and
            // self-limiting: the first thing it does is consult the flag.
            embeddedTransferViewModel.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self, self.view.window != nil else { return }
                    self.presentTransferTimingSheetIfNeeded()
                }
                .store(in: &cancellables)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Also on the way back from a pushed step, which restored the bar on
        // its own way out.
        applyTabBarVisibility()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Programmatic dismissal does not call
        // `presentationControllerDidDismiss`. Clear the explicit sheet pause
        // here as well so returning from transaction details can resume the
        // same receive session (or start a fresh "Receive another" session).
        viewModel.setReceiptWatchingObscured(false)
        isPushingReceiveStep = false
        receiveStepObservers.removeAll()
        viewModel.setReceiveSurfaceVisible(true)
        if timingSheetPendingAppearance {
            timingSheetPendingAppearance = false
            presentTransferTimingSheetIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stepping deeper into the receive flow is not leaving it. Everything
        // else — a tab change, a dismissal, a pop — still puts the session to
        // sleep.
        guard !isPushingReceiveStep else { return }
        viewModel.setReceiveSurfaceVisible(false)
        // Leaving for another tab, or being dismissed — either way the bar is
        // not ours to keep hidden. A pushed step hides it for itself.
        if presentingViewController == nil {
            tabBarController?.setTabBarHidden(false, animated: false)
        }
    }

    // MARK: - Actions

    /// Copies only. The "Copied" toast is drawn by the SwiftUI screen — this
    /// controller has no view of its own to hang it on that isn't behind the
    /// tab bar.
    private func copyCurrentAddress() {
        viewModel.copyCurrentAddressToPasteboard()
    }

    private func shareCurrentAddress() {
        guard let address = viewModel.currentAddress else { return }
        // The share control lives in the SwiftUI hierarchy, so there is no
        // sender view to anchor to — the helper's centred default carries the
        // popover anchor iPad requires.
        viewModel.setReceiptWatchingObscured(true)
        dw_presentActivityViewController(
            activityItems: [address],
            dismissal: { [weak self] in
                self?.viewModel.setReceiptWatchingObscured(false)
            })
    }

    private func pushSpecifyAmount() {
        let specify = SpecifyAmountViewController.controller()
        specify.delegate = self
        isPushingReceiveStep = true
        observeReceiptWhileOnReceiveStep()
        pushWithoutTabBar(specify)
    }

    /// Bring the user back to the receipt from wherever in the receive flow
    /// they are standing.
    ///
    /// Armed by the push, not by the sheet: the sheet is optional — Specify
    /// Amount can be sat on with nothing over it — and a receipt arriving there
    /// used to leave the user one screen short of the thing they were waiting
    /// for, with no way to know it had happened.
    private func observeReceiptWhileOnReceiveStep() {
        receiveStepObservers.removeAll()

        viewModel.$receipt
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.receiveStepObservers.removeAll()

                guard let sheet = self.requestAmountController else {
                    self.returnToLandingFromReceiveStep()
                    return
                }
                // The sheet first, then the step under it — dismissing and
                // popping in the same turn runs the two animations over each
                // other.
                self.requestAmountObservers.removeAll()
                self.requestAmountController = nil
                sheet.dismiss(animated: true) { [weak self] in
                    self?.returnToLandingFromReceiveStep()
                }
            }
            .store(in: &receiveStepObservers)
    }

    /// The base class routes a scanned payment straight into the payment
    /// processor (its `DWQRScanModelDelegate` conformance is a private
    /// class extension, so this can't be `override` — the matching selector
    /// shadows it through ObjC dispatch). Every scan on the landing
    /// originates from the Send tab's embedded form, so fill that form —
    /// destination-type detection and the From picker then apply to scanned
    /// addresses exactly like typed/pasted ones.
    @objc(qrScanModel:didScanPaymentInput:)
    func qrScanModel(_ viewModel: DWQRScanModel, didScanPaymentInput paymentInput: DWPaymentInput) {
        dismiss(animated: true) { [weak self] in
            self?.embeddedSendViewModel.ingestScannedInput(paymentInput)
        }
    }

    /// First-ever visit to the free-form Internal tab: explain transfer
    /// timing before the user composes a transfer. The form is already
    /// embedded underneath; "I got it" (not the X) acknowledges for good.
    /// Puts the landing on `tab` without rebuilding it — the tab-bar entry
    /// points select this controller rather than presenting a copy.
    func select(tab: PaymentsLandingTab) {
        viewModel.activeTab = tab
    }

    #if DASHPAY
    /// "Send to username" → the contact book. The same screen the Send-to-a-
    /// contact entry opens (`PayableViewController.performPayToDashPayUser`);
    /// paying happens from a contact's profile sheet, so this row's whole job
    /// is getting the user there.
    ///
    /// Selects the contacts TAB rather than showing a copy of the screen.
    ///
    /// `ContactsScreen` is a tab root and only works as one. It runs its banner
    /// under the status bar (`ignoresSafeArea(edges: .top)`) and lets the safe
    /// area place the title inside it, which collapses in a sheet; and it
    /// carries no dismiss control, because a tab root never needs one — pushing
    /// it onto this stack left the user with no way back, since the payments
    /// navigation controller hides its bar.
    ///
    /// The tab is there whenever this row is: both appear only with a DashPay
    /// identity. The tab bar is the way back, and there stays exactly one
    /// contacts screen in the app.
    private func showContactBook() {
        guard let tabBarController = tabBarController as? MainTabbarController,
              tabBarController.showContacts()
        else {
            // No contacts tab means no identity — which is also the condition
            // that hides the row. Reaching here would be a bug, and silently
            // doing nothing is how it would stay invisible.
            assertionFailure("Send to username offered without a contacts tab")
            return
        }
    }
    #else
    private func showContactBook() {}
    #endif

    /// The X above the Internal form. Dismisses where something presented this
    /// landing, and leaves for the history where nothing did — as the payments
    /// tab's root, `dismiss` is a no-op, which is the bug the receive receipt's
    /// Done button had.
    private func leaveLanding() {
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            (tabBarController as? MainTabbarController)?.showHome()
        }
    }

    /// The tab bar goes while the landing is up, and the X above the selector
    /// takes its place as the way out.
    ///
    /// The Internal tab forced the question — it embeds the transfer form now,
    /// and its keypad and Continue button were sharing the bottom of the screen
    /// with the bar, which the payments tab's own rule already forbids: the bar
    /// is gone from the first step that asks for an amount. Hiding it on that
    /// tab alone, though, would flicker the chrome in and out as the user moved
    /// between the three, so it goes for the whole landing.
    ///
    /// Only meaningful on the tab. The balance-row sheets are presented and
    /// have no tab bar to hide.
    private func applyTabBarVisibility() {
        guard let tabBarController, presentingViewController == nil else { return }
        tabBarController.setTabBarHidden(true, animated: true)
    }

    /// "Swap to other crypto" → the Dash DEX portal.
    ///
    /// Behind the same authentication gate the Home shortcut puts it behind:
    /// the portal is a spending surface, and a destination that asks for a PIN
    /// from one entry point and not another is not a gate at all.
    private func presentDashDEX() {
        AuthenticationService.shared.authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            alertIfLockout: true
        ) { [weak self] authenticated, _, _ in
            guard authenticated, let self else { return }
            let controller = SwapKitPortalViewController()
            controller.hidesBottomBarWhenPushed = true
            let navigationController = BaseNavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .fullScreen
            self.present(navigationController, animated: true)
        }
    }

    /// Send card → the address-entry form. Pushed rather than embedded: the
    /// landing's Send tab is now the destination picker, not the form.
    /// Where Done on a receive receipt goes.
    ///
    /// Presented as a sheet there is something to dismiss; as the payments
    /// tab's root there is not — `dismiss` was a no-op, which is why the button
    /// appeared dead. Leaving for the history is what finishing means there,
    /// and it is where the receipt's transaction shows up.
    private func finishReceiving() {
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            (tabBarController as? MainTabbarController)?.showHome()
        }
    }

    /// Mirror the session into the specify-amount sheet, and close that sheet
    /// the moment a payment lands — the receipt is on the surface behind it,
    /// and a QR for an amount just paid would be the stalest thing on screen.
    private func observeReceiptWhileRequestingAmount(_ controller: RequestAmountHostingController) {
        requestAmountObservers.removeAll()

        viewModel.$isWatchingForReceipt
            .receive(on: RunLoop.main)
            .sink { [weak controller] watching in
                controller?.setWatchingForReceipt(watching)
            }
            .store(in: &requestAmountObservers)

    }

    /// Pop back to the landing from a pushed receive step, if that is where we
    /// are. `isPushingReceiveStep` is the flag for exactly that state, and
    /// `viewDidAppear` clears it on arrival.
    ///
    /// The pop targets the STACK MEMBER holding this controller, not this
    /// controller. In the payments tab the landing is a child of
    /// `PaymentsTabRootController`, which is what the navigation stack
    /// actually contains; presented, it is the navigation controller's own
    /// root. Popping to `self` therefore named a controller that is not in the
    /// stack at all, and UIKit had nothing to pop to — the sheet closed and
    /// nothing else moved.
    private func returnToLandingFromReceiveStep() {
        guard isPushingReceiveStep, let navigationController else { return }

        let host = navigationController.viewControllers.first { controller in
            controller === self || controller.children.contains { $0 === self }
        }
        guard let host, navigationController.topViewController !== host else { return }

        navigationController.popToViewController(host, animated: true)
    }

    private func pushSendToAddress() {
        pushWithoutTabBar(SendScreenViewController())
    }

    /// The landing keeps the tab bar; everything it pushes is a step in a
    /// flow and takes the whole screen.
    private func pushWithoutTabBar(_ controller: UIViewController) {
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    /// Whether a shielded balance is one of the transfer's two ends.
    ///
    /// The sheet explains why a shielded transfer takes longer, so it has
    /// nothing to say about a route that does not touch one.
    private var transferTouchesShieldedBalance: Bool {
        embeddedTransferViewModel.source == .shielded
            || embeddedTransferViewModel.destination == .balance(.shielded)
    }

    private func presentTransferTimingSheetIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.shieldedBalanceTimingShownKey),
              viewModel.activeTab == .internalTransfer,
              transferTouchesShieldedBalance,
              presentedViewController == nil
        else { return }
        // Written on presentation, not on the confirm button. The sheet is a
        // `pageSheet` and can be swiped away; recording it only when the button
        // is tapped meant anyone who dismisses that way was told again, and
        // again, every time they opened the tab. "Shown once" is the rule, and
        // showing it is what satisfies it.
        UserDefaults.standard.set(true, forKey: Self.shieldedBalanceTimingShownKey)
        viewModel.setReceiptWatchingObscured(true)
        let host = UIHostingController(
            rootView: TransferTimingSheet(onConfirm: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.viewModel.setReceiptWatchingObscured(false)
                }
            }))
        host.modalPresentationStyle = .pageSheet
        // Fill the whole sheet, including the bottom safe-area strip, with the
        // sheet background — the detent paints that strip itself.
        host.view.backgroundColor = UIColor(Color.dash.primaryBackground)

        if let sheet = host.sheetPresentationController {
            // `BottomSheet` draws its own grabber.
            sheet.prefersGrabberVisible = false
            if #unavailable(iOS 26.0) {
                sheet.preferredCornerRadius = 24
            }
            // SwiftUI's `.presentationDetents` does not bridge to a
            // `UIHostingController` presented with `present()` — UIKit falls
            // back to `.large` — so the content is measured here and given a
            // matching detent. Mirrors `HomeViewController`'s reminder sheet.
            if #available(iOS 16.0, *) {
                let width = view.bounds.width
                let bottomInset = view.window?.safeAreaInsets.bottom ?? 0
                let contentHeight = host
                    .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                    .height
                sheet.detents = [.custom { context in
                    min(contentHeight + bottomInset, context.maximumDetentValue)
                }]
            } else {
                sheet.detents = [.medium()]
            }
        }
        present(host, animated: true) { [weak self, weak host] in
            host?.presentationController?.delegate = self
        }
    }

    private func showTransaction(txid: Data) {
        guard viewModel.allowsTransactionDetails,
              let transaction = SwiftDashSDKWalletSource
                  .fetch(txids: Set([txid]))?.transactions.first
        else { return }
        viewModel.setReceiptWatchingObscured(true)
        let controller = ReceiptTransactionDetailViewController(model: TxDetailModel(transaction: transaction))
        controller.onDismiss = { [weak self] in
            self?.viewModel.setReceiptWatchingObscured(false)
        }
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true) { [weak self, weak navigationController] in
            navigationController?.presentationController?.delegate = self
        }
    }

    private static func tabRawValue(for objcCase: Int) -> String {
        switch objcCase {
        case 0: return PaymentsLandingTab.receive.rawValue
        case 1: return PaymentsLandingTab.internalTransfer.rawValue
        case 2: return PaymentsLandingTab.send.rawValue
        default: return PaymentsLandingTab.send.rawValue
        }
    }
}

// MARK: NavigationBarDisplayable

// Without this, BaseNavigationController's willShow pass re-shows the
// (transparent) navigation bar — its safe-area inset was pushing the
// whole landing content ~50pt down in both the sheet and full-screen
// presentations. The landing draws its own chrome; no bar, no back button.
extension PaymentsLandingHostingController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

// MARK: SpecifyAmountViewControllerDelegate

extension PaymentsLandingHostingController: SpecifyAmountViewControllerDelegate {
    func specifyAmountViewController(_ vc: SpecifyAmountViewController, didInput amount: UInt64) {
        // The SwiftUI sheet, not `DWRequestAmountViewController`: this landing
        // is the redesigned path, and it sizes its own detent. The ObjC pair is
        // still what the legacy `ReceiveViewController` presents.
        //
        // The session keeps running behind THIS sheet, unlike every other one
        // the landing presents.
        //
        // #1041 suspends watching whenever something covers the receive UI, and
        // for the share sheet or transaction details that is right — the user
        // is not presenting anything. This sheet is the opposite: a QR with the
        // amount already in it, held up for someone to pay. Pausing detection
        // on the handoff surface would pause it exactly where the feature is
        // for. Nothing is lost either way — the session's baseline survives a
        // suspend — but the sheet could not say it was watching, and could not
        // get out of the way when the payment landed.
        let requestController = RequestAmountHostingController.present(
            from: self,
            model: DWReceiveModel(amount: amount),
            delegate: self)
        requestAmountController = requestController
        requestController.setWatchingForReceipt(viewModel.isWatchingForReceipt)
        observeReceiptWhileRequestingAmount(requestController)
    }
}

// MARK: RequestAmountHostingControllerDelegate

extension PaymentsLandingHostingController: RequestAmountHostingControllerDelegate {
    /// The requested amount arrived, which this sheet notices through its own
    /// balance-change observer. Getting out of the way is all that is left to
    /// do: the attended receipt on the surface behind already says what landed,
    /// with the rail, the status and the transaction.
    ///
    /// It used to pop the navigation stack and raise an info HUD as well. Both
    /// were written for a landing that had been PUSHED — as the payments tab's
    /// root there is nothing to pop, and that HUD went onto the navigation
    /// controller's view, where it drew underneath the tab bar as an
    /// unidentifiable smudge.
    func requestAmountHostingController(
        _ controller: RequestAmountHostingController,
        didReceiveAmountWithInfo info: String
    ) {
        controller.dismiss(animated: true) {
            // No un-obscuring: this sheet never suspended the session. What
            // does end here is the sheet's own mirroring of it.
            self.requestAmountObservers.removeAll()
            self.requestAmountController = nil
        }
    }
}

// MARK: UIAdaptivePresentationControllerDelegate

extension PaymentsLandingHostingController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        viewModel.setReceiptWatchingObscured(false)
    }
}

/// `UIAdaptivePresentationControllerDelegate` is only notified for interactive
/// dismissals. Transaction details close themselves programmatically, so carry
/// that completion back to the attended receive session explicitly.
private final class ReceiptTransactionDetailViewController: TXDetailViewController {
    var onDismiss: (() -> Void)?

    override func closeAction() {
        let onDismiss = onDismiss
        dismiss(animated: true, completion: onDismiss)
    }
}
