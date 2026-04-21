//
//  SendScreenViewController.swift
//  DashWallet
//

import SwiftUI
import UIKit

@objc(DWSendScreenViewController)
final class SendScreenViewController: DWBasePayViewController {

    @objc var homeModel: DWHomeProtocol? {
        didSet { dataProvider = homeModel?.getDataProvider() }
    }

    private let sendViewModel = SendViewModel()
    private lazy var hostingController: UIHostingController<SendScreen> = {
        let screen = SendScreen(
            viewModel: sendViewModel,
            onClose: { [weak self] in self?.dismiss(animated: true) },
            onScanQR: { [weak self] in self?.performScanQRCodeAction() },
            onContinueCore: { [weak self] address in self?.continueCore(address: address) },
            onContinuePlatform: { [weak self] address in self?.continuePlatform(address: address) })
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
    }

    // MARK: - Routing

    private func continueCore(address: String) {
        let chain = DWEnvironment.sharedInstance().currentChain
        guard address.isValidDashAddress(on: chain) else { return }
        guard let url = URL(string: "dash:\(address)") else { return }
        performPayToURL(url)
    }

    private func continuePlatform(address: String) {
        guard Bech32m.isValidPlatformAddress(address) else { return }
        let confirm = PlatformSendConfirmScreen(destination: address) { [weak self] in
            self?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: confirm)
        host.modalPresentationStyle = .automatic
        present(host, animated: true)
    }
}
