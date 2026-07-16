//
//  PaymentsLandingHostingController.swift
//  DashWallet
//

import SwiftUI
import UIKit

@objc(DWPaymentsLandingHostingController)
final class PaymentsLandingHostingController: DWBasePayViewController {

    private let viewModel: PaymentsLandingViewModel
    /// Non-nil only for the balance-row receive sheet: the Internal tab
    /// then embeds the transfer form directly, preconfigured as a transfer
    /// INTO the balance whose arrow opened the sheet (Core/Platform receive
    /// from Shielded; Shielded receives from Core). The swap badge on the
    /// form can still reverse it.
    private let embeddedTransferViewModel: InternalTransferViewModel?
    private lazy var hostingController: UIHostingController<PaymentsLandingScreen> = {
        let screen = PaymentsLandingScreen(
            viewModel: viewModel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onCopyAddress: { [weak self] in self?.copyCurrentAddress() },
            onShareAddress: { [weak self] in self?.shareCurrentAddress() },
            onSpecifyAmount: { [weak self] in self?.pushSpecifyAmount() },
            onScanQR: { [weak self] in self?.performScanQRCodeAction() },
            onSendToAddress: { [weak self] in self?.pushSendScreen() },
            onShieldedBalance: { [weak self] in self?.handleShieldedBalanceTap() },
            embeddedTransferViewModel: embeddedTransferViewModel,
            onTransferCompleted: { [weak self] in self?.dismiss(animated: true) },
            showsHeader: showsHeader)
        return UIHostingController(rootView: screen)
    }()

    /// False for the balance-row receive sheet (grabber + hero selector
    /// only); the full-screen landing keeps its X + title row.
    private let showsHeader: Bool

    private static let shieldedBalanceTimingShownKey = "DWShieldedBalanceTimingShown"

    @objc init(activeTab: Int) {
        let resolved = PaymentsLandingTab.allCases.first { $0.rawValue == Self.tabRawValue(for: activeTab) }
            ?? .send
        self.viewModel = PaymentsLandingViewModel(activeTab: resolved)
        self.embeddedTransferViewModel = nil
        self.showsHeader = true
        super.init(nibName: nil, bundle: nil)
    }

    /// `receiveNetwork` preselects the Receive tab's Core/Platform/Shielded
    /// toggle — the balance-row receive arrows open the landing on the
    /// balance the user tapped. `visibleTabs` narrows the hero selector
    /// (the receive sheet shows only Receive + Internal), and
    /// `embedInternalTransfer` makes the Internal tab the transfer form
    /// itself rather than the action-row list.
    init(activeTab: PaymentsLandingTab,
         receiveNetwork: ChainNetwork = .core,
         visibleTabs: [PaymentsLandingTab] = PaymentsLandingTab.allCases,
         embedInternalTransfer: Bool = false,
         showsHeader: Bool = true) {
        self.viewModel = PaymentsLandingViewModel(
            activeTab: activeTab, network: receiveNetwork, visibleTabs: visibleTabs)
        self.showsHeader = showsHeader
        if embedInternalTransfer {
            let transferViewModel = InternalTransferViewModel()
            transferViewModel.applyReceiveRoute(into: receiveNetwork)
            self.embeddedTransferViewModel = transferViewModel
        } else {
            self.embeddedTransferViewModel = nil
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        let share = UIActivityViewController(activityItems: [address], applicationActivities: nil)
        present(share, animated: true)
    }

    private func pushSpecifyAmount() {
        let specify = SpecifyAmountViewController.controller()
        specify.delegate = self
        navigationController?.pushViewController(specify, animated: true)
    }

    private func pushSendScreen() {
        let controller = SendScreenViewController()
        navigationController?.pushViewController(controller, animated: true)
    }

    private func handleShieldedBalanceTap() {
        let alreadyShown = UserDefaults.standard.bool(forKey: Self.shieldedBalanceTimingShownKey)
        if alreadyShown {
            pushInternalTransfer()
        } else {
            presentTransferTimingSheet()
        }
    }

    private func presentTransferTimingSheet() {
        let host = UIHostingController(
            rootView: TransferTimingSheet(onConfirm: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.shieldedBalanceTimingShownKey)
                self?.dismiss(animated: true) {
                    self?.pushInternalTransfer()
                }
            }))
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    /// Pushes the internal-transfer screen onto the landing modal's own
    /// navigation stack, keeping the user inside the same presentation.
    /// (Full-landing path only — the receive sheet embeds the form in its
    /// Internal tab instead; see `embeddedTransferViewModel`.)
    private func pushInternalTransfer() {
        let target = InternalTransferHostingController()
        navigationController?.pushViewController(target, animated: true)
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
        present(requestController, animated: true)
    }
}

// MARK: DWRequestAmountViewControllerDelegate

extension PaymentsLandingHostingController: DWRequestAmountViewControllerDelegate {
    func requestAmountViewController(_ controller: DWRequestAmountViewController, didReceiveAmountWithInfo info: String) {
        controller.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)

            let popAnimationDuration = 300
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(popAnimationDuration)) {
                self.navigationController?.view.dw_showInfoHUD(withText: info)
            }
        }
    }
}
