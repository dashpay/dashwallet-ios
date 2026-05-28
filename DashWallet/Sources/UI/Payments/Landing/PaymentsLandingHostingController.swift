//
//  PaymentsLandingHostingController.swift
//  DashWallet
//

import SwiftUI
import UIKit

@objc(DWPaymentsLandingHostingController)
final class PaymentsLandingHostingController: DWBasePayViewController {

    @objc var homeModel: DWHomeProtocol? {
        didSet {
            if let provider = homeModel?.getDataProvider() {
                dataProvider = provider
            }
        }
    }

    private let viewModel: PaymentsLandingViewModel
    private lazy var hostingController: UIHostingController<PaymentsLandingScreen> = {
        let screen = PaymentsLandingScreen(
            viewModel: viewModel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onCopyAddress: { [weak self] in self?.copyCurrentAddress() },
            onShareAddress: { [weak self] in self?.shareCurrentAddress() },
            onSpecifyAmount: { [weak self] in self?.pushSpecifyAmount() },
            onImportPrivateKey: { [weak self] in self?.performScanQRCodeAction() },
            onScanQR: { [weak self] in self?.performScanQRCodeAction() },
            onSendToAddress: { [weak self] in self?.pushSendScreen() })
        return UIHostingController(rootView: screen)
    }()

    @objc init(activeTab: Int) {
        let resolved = PaymentsLandingTab.allCases.first { $0.rawValue == Self.tabRawValue(for: activeTab) }
            ?? .send
        self.viewModel = PaymentsLandingViewModel(activeTab: resolved)
        super.init(nibName: nil, bundle: nil)
    }

    init(activeTab: PaymentsLandingTab) {
        self.viewModel = PaymentsLandingViewModel(activeTab: activeTab)
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
        specify.delegate = ReceiveSpecifyAmountRouter.shared
        navigationController?.pushViewController(specify, animated: true)
    }

    private func pushSendScreen() {
        let controller = SendScreenViewController()
        controller.homeModel = homeModel
        navigationController?.pushViewController(controller, animated: true)
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
