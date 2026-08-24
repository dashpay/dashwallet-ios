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
            showsHeader: showsHeader)
        return UIHostingController(rootView: screen)
    }()

    /// False for the balance-row receive sheet (grabber + hero selector
    /// only); the full-screen landing keeps its X + title row.
    private let showsHeader: Bool

    private static let shieldedBalanceTimingShownKey = "DWShieldedBalanceTimingShown"

    private var cancellables = Set<AnyCancellable>()
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
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Programmatic dismissal does not call
        // `presentationControllerDidDismiss`. Clear the explicit sheet pause
        // here as well so returning from transaction details can resume the
        // same receive session (or start a fresh "Receive another" session).
        viewModel.setReceiptWatchingObscured(false)
        viewModel.setReceiveSurfaceVisible(true)
        if timingSheetPendingAppearance {
            timingSheetPendingAppearance = false
            presentTransferTimingSheetIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.setReceiveSurfaceVisible(false)
    }

    // MARK: - Actions

    private func copyCurrentAddress() {
        viewModel.copyCurrentAddressToPasteboard()
        view.dw_showInfoHUD(
            withText: NSLocalizedString("Copied", comment: ""),
            offsetForNavBar: false)
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
        navigationController?.pushViewController(specify, animated: true)
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
    private func presentTransferTimingSheetIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.shieldedBalanceTimingShownKey),
              presentedViewController == nil
        else { return }
        viewModel.setReceiptWatchingObscured(true)
        let host = UIHostingController(
            rootView: TransferTimingSheet(onConfirm: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.shieldedBalanceTimingShownKey)
                self?.dismiss(animated: true) {
                    self?.viewModel.setReceiptWatchingObscured(false)
                }
            }))
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
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
        let model = DWReceiveModel(amount: amount)

        let requestController = DWRequestAmountViewController(model: model)
        requestController.delegate = self
        viewModel.setReceiptWatchingObscured(true)
        present(requestController, animated: true) { [weak self, weak requestController] in
            requestController?.presentationController?.delegate = self
        }
    }
}

// MARK: DWRequestAmountViewControllerDelegate

extension PaymentsLandingHostingController: DWRequestAmountViewControllerDelegate {
    func requestAmountViewController(_ controller: DWRequestAmountViewController, didReceiveAmountWithInfo info: String) {
        controller.dismiss(animated: true) {
            self.viewModel.setReceiptWatchingObscured(false)
            self.navigationController?.popViewController(animated: true)

            let popAnimationDuration = 300
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(popAnimationDuration)) {
                self.navigationController?.view.dw_showInfoHUD(withText: info)
            }
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
