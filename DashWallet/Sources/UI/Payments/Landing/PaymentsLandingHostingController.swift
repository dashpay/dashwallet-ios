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
            onInternalTransfer: { [weak self] target in self?.pushInternalTransfer(to: target) },
            onSendToAddress: { [weak self] in self?.pushSendToAddress() },
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
         showsHeader: Bool = true) {
        self.viewModel = PaymentsLandingViewModel(
            activeTab: activeTab, network: receiveNetwork, visibleTabs: visibleTabs)
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
            showsHeader: false)
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
        if timingSheetPendingAppearance {
            timingSheetPendingAppearance = false
            presentTransferTimingSheetIfNeeded()
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
        dw_presentActivityViewController(activityItems: [address])
    }

    private func pushSpecifyAmount() {
        let specify = SpecifyAmountViewController.controller()
        specify.delegate = self
        pushWithoutTabBar(specify)
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

    /// Internal card → the transfer form, on this controller's own navigation
    /// stack so the user stays inside the payments tab.
    private func pushInternalTransfer(to destination: TransferDestination) {
        let controller = InternalTransferHostingController(transferTo: destination)
        pushWithoutTabBar(controller)
    }

    /// Send card → the address-entry form. Pushed rather than embedded: the
    /// landing's Send tab is now the destination picker, not the form.
    private func pushSendToAddress() {
        pushWithoutTabBar(SendScreenViewController())
    }

    /// The landing keeps the tab bar; everything it pushes is a step in a
    /// flow and takes the whole screen.
    private func pushWithoutTabBar(_ controller: UIViewController) {
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    private func presentTransferTimingSheetIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.shieldedBalanceTimingShownKey),
              presentedViewController == nil
        else { return }
        let host = UIHostingController(
            rootView: TransferTimingSheet(onConfirm: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.shieldedBalanceTimingShownKey)
                self?.dismiss(animated: true)
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
        present(host, animated: true)
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
        RequestAmountHostingController.present(
            from: self,
            model: DWReceiveModel(amount: amount),
            delegate: self)
    }
}

// MARK: RequestAmountHostingControllerDelegate

extension PaymentsLandingHostingController: RequestAmountHostingControllerDelegate {
    func requestAmountHostingController(
        _ controller: RequestAmountHostingController,
        didReceiveAmountWithInfo info: String
    ) {
        controller.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)

            let popAnimationDuration = 300
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(popAnimationDuration)) {
                self.navigationController?.view.dw_showInfoHUD(withText: info)
            }
        }
    }
}
