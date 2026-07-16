//
//  InternalTransferHostingController.swift
//  DashWallet
//

import SwiftUI
import UIKit

@objc(DWInternalTransferHostingController)
final class InternalTransferHostingController: UIViewController {

    private let viewModel = InternalTransferViewModel()

    /// Open the screen pre-filled for the "fund your Shielded balance"
    /// flow (Join DashPay readiness): direction is already the default
    /// `.toShielded`; this just seeds the amount so the user can
    /// confirm instead of retyping the suggested deposit.
    convenience init(prefillDashAmount: Decimal) {
        self.init(nibName: nil, bundle: nil)
        // `Decimal`'s description always uses a dot, which the view
        // model's parser normalises for — locale-safe as a seed value.
        viewModel.amountText = "\(prefillDashAmount)"
    }

    private lazy var hostingController: UIHostingController<InternalTransferScreen> = {
        let screen = InternalTransferScreen(viewModel: viewModel) { [weak self] in
            // After a successful transfer the user taps "Done" inside the
            // confirm sheet; the screen forwards that to us so we can
            // leave — pop when pushed (landing / readiness flows), dismiss
            // if some future presenter shows this standalone as a sheet.
            guard let self else { return }
            if let navigationController = self.navigationController {
                navigationController.popViewController(animated: true)
            } else {
                self.dismiss(animated: true)
            }
        }
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
        // Pushed: the navigation bar provides the top spacing. Presented
        // as a sheet: there is no bar, so inset the content below the
        // grabber instead of letting the title crowd the sheet's edge.
        let isSheet = navigationController == nil
        let topInset: CGFloat = isSheet ? 28.0 : 0.0
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset),
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
