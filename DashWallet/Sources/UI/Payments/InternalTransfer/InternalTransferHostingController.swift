//
//  InternalTransferHostingController.swift
//  DashWallet
//

import SwiftUI
import UIKit

@objc(DWInternalTransferHostingController)
final class InternalTransferHostingController: UIViewController {

    private let viewModel = InternalTransferViewModel()

    private lazy var hostingController: UIHostingController<InternalTransferScreen> = {
        let screen = InternalTransferScreen(
            viewModel: viewModel,
            onContinue: { /* no-op for now — shielding logic lands later */ })
        return UIHostingController(rootView: screen)
    }()

    private var previousNavBarHidden: Bool = false

    override func viewDidLoad() {
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(previousNavBarHidden, animated: animated)
    }
}
