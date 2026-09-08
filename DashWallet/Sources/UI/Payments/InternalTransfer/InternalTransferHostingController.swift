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

    /// Opens the form with `destination` already selected as the To endpoint —
    /// the payments landing's Internal card picks where a transfer is headed
    /// before any amount is typed.
    ///
    /// A balance destination is preselected, not pinned: the view model moves
    /// the From side off it if that is where it currently sits, the From row
    /// opens the source picker, and the swap badge can still exchange the
    /// two. Identity fixes the To card instead — the source side does not
    /// offer identity (the app implements identity top-up but not withdrawal
    /// yet), so there is nothing to swap into; the From row still picks among
    /// all three balances.
    convenience init(transferTo destination: TransferDestination) {
        self.init(nibName: nil, bundle: nil)
        viewModel.selectStandaloneDestination(destination)
    }

    private lazy var hostingController: UIHostingController<InternalTransferScreen> = {
        var screen = InternalTransferScreen(viewModel: viewModel) { [weak self] in
            // Confirm hands the transfer to `InternalTransferRunner`; the
            // screen waits for the confirm sheet to finish closing and then
            // calls this, so it fires while the transfer is still running.
            // Leave for the history, where the outcome shows up: the home tab
            // when this was pushed inside the tab bar, otherwise just pop or
            // dismiss whatever presented us.
            self?.leaveForHistory()
        }
        // Only when pushed: presented as a sheet there is nothing to go back
        // to, and the grabber is the way out.
        if navigationController != nil {
            screen.onBack = { [weak self] in self?.leave() }
        }
        return UIHostingController(rootView: screen)
    }()

    private func leave(completion: (() -> Void)? = nil) {
        if let navigationController {
            // `popViewController` takes no completion handler, so the pop's own
            // CoreAnimation transaction carries one.
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            navigationController.popViewController(animated: true)
            CATransaction.commit()
        } else {
            dismiss(animated: true, completion: completion)
        }
    }

    /// Back to where the transfer becomes visible. The runner announces the
    /// outcome there, and — for the routes that write one — the history row
    /// carries it.
    ///
    /// The tab change waits for the pop: run together, the stack slid back
    /// while the tab swapped underneath it, and the two read as one jolt. Held
    /// onto beforehand because popping detaches this controller, and
    /// `tabBarController` is nil by the time the completion runs.
    private func leaveForHistory() {
        let tabBarController = tabBarController as? MainTabbarController
        leave { tabBarController?.showHome() }
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
