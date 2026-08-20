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

    /// Opens the form with `target` already selected as the To endpoint —
    /// the payments landing's Internal card picks where a transfer is headed
    /// before any amount is typed.
    ///
    /// Preselected, not pinned: both cards stay pickers, and the view model
    /// moves the From side off `target` if that is where it currently sits.
    convenience init(transferTo target: ChainNetwork) {
        self.init(nibName: nil, bundle: nil)
        viewModel.selectStandaloneTarget(target)
    }

    private lazy var hostingController: UIHostingController<InternalTransferScreen> = {
        var screen = InternalTransferScreen(viewModel: viewModel) { [weak self] in
            // After a successful transfer the user taps "Done" inside the
            // confirm sheet; the screen forwards that to us so we can
            // leave — pop when pushed (landing / readiness flows), dismiss
            // if some future presenter shows this standalone as a sheet.
            self?.leave()
        }
        // Only when pushed: presented as a sheet there is nothing to go back
        // to, and the grabber is the way out.
        if navigationController != nil {
            screen.onBack = { [weak self] in self?.leave() }
        }
        return UIHostingController(rootView: screen)
    }()

    private func leave() {
        if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_background()

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        // Pushed: the screen draws its own `NavigationBar`, which carries the
        // top spacing. Presented as a sheet: no bar, so inset the content
        // below the grabber instead of letting the title crowd the edge.
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
}

// MARK: - NavigationBarDisplayable

/// The screen draws the design system's `NavigationBar` itself, so the UIKit
/// one has to stay down. Without this, `BaseNavigationController`'s `willShow`
/// pass falls back to showing it and the screen gets two back buttons.
extension InternalTransferHostingController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}
