//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import UIKit

// MARK: - MayaTransactionStatusHostingController

/// Full-screen owner of the Maya transaction status flow (pending → processing →
/// success / failure). Pushed onto the Maya navigation stack once a swap is submitted.
///
/// Back navigation is intentionally blocked while this screen is on top: the UIKit nav bar is
/// hidden, `shouldPopViewController()` returns false, and the interactive swipe-back gesture is
/// disabled for as long as the screen is visible.
final class MayaTransactionStatusHostingController: UIViewController, NavigationBarDisplayable, NavigationStackControllable {
    var isNavigationBarHidden: Bool { true }

    /// Defense in depth: block the UIKit back-button path even though the nav bar is hidden.
    func shouldPopViewController() -> Bool { false }

    private let viewModel: OrderPreviewViewModel

    init(viewModel: OrderPreviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let statusView = MayaTransactionStatusView(
            viewModel: viewModel,
            onDone: { [weak self] in
                guard let self else { return }
                // Return to Home — handle BOTH entry paths:
                // • Shortcuts: the Buy&Sell/Maya flow is a modal presented over the tab bar → dismiss.
                // • More menu: the flow is PUSHED inside a tab's nav → pop it away and switch to the
                //   Home tab (index 0 = MainTabbarTabs.home). dismiss would be a no-op there, so branch.
                if self.navigationController?.presentingViewController != nil {
                    self.navigationController?.dismiss(animated: true)
                } else {
                    // `self.tabBarController` can be nil here (hidesBottomBarWhenPushed), so find the
                    // app's tab bar controller via the window hierarchy and select the Home tab.
                    let tab = self.tabBarController
                        ?? self.view.window?.rootViewController?.dw_firstTabBarController()
                    self.navigationController?.popToRootViewController(animated: false)
                    tab?.selectedIndex = 0
                }
            },
            onClose: { [weak self] in
                // Failure dismissed → return to the Maya Portal, never to Order Preview / Convert.
                guard let nav = self?.navigationController else { return }
                nav.popToViewController(ofType: MayaPortalViewController.self, animated: true)
            },
            onRetry: { [weak self] in
                self?.handleRetry()
            }
        )

        let hostingController = UIHostingController(rootView: statusView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // No swipe-back while the status screen is active.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore normal swipe-back for whatever screen comes next (Home / Portal / Order Preview).
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    // MARK: - Retry

    private func handleRetry() {
        Task { [weak self] in
            guard let self else { return }

            guard let freshViewModel = await self.viewModel.retryQuote() else {
                // Quote refresh failed — the view model updated `swapStatus` with the new
                // reason, so we stay on the failed screen (it re-renders automatically).
                return
            }

            guard let nav = self.navigationController else { return }

            // Replace BOTH the failed status screen and the stale Order Preview beneath it with
            // a fresh Order Preview built from the new quote. Back from the new Order Preview
            // therefore returns to Convert, not to a stale preview.
            var controllers = nav.viewControllers
            if controllers.last === self {
                controllers.removeLast()
            }
            if controllers.last is OrderPreviewHostingController {
                controllers.removeLast()
            }
            controllers.append(OrderPreviewHostingController(viewModel: freshViewModel))
            nav.setViewControllers(controllers, animated: true)
        }
    }
}

// MARK: - MayaTransactionStatusView

/// Full-screen status content. Renders one of the Maya status views based on `swapStatus`,
/// switching content in place (no sheet) so success / failure cannot flicker or be dismissed
/// by SwiftUI sheet-state changes.
private struct MayaTransactionStatusView: View {
    @ObservedObject var viewModel: OrderPreviewViewModel
    let onDone: () -> Void
    let onClose: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.swapStatus {
        case .idle, .pendingConfirmation:
            pending(message: NSLocalizedString(
                "Your Dash transaction has been sent. Waiting for block confirmation — this takes 2–5 minutes because Maya swaps don't use InstantSend.",
                comment: "Maya"
            ))
        case .processingSwap:
            pending(message: NSLocalizedString(
                "Maya Protocol has received your transaction and is processing the swap.",
                comment: "Maya"
            ))
        case .completed:
            MayaTransactionSuccessView(
                coinCode: viewModel.coin.code,
                coinName: viewModel.coin.name,
                onDone: onDone
            )
        case .failed(let reason):
            MayaTransactionFailureView(
                reason: reason,
                isRetrying: viewModel.isRetrying,
                transactionHash: viewModel.submittedTxId,
                onRetry: onRetry,
                onCancel: onClose
            )
        }
    }

    private func pending(message: String) -> some View {
        MayaTransactionPendingView(
            message: message,
            onGoHome: onDone
        )
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension UIViewController {
    /// Finds the first UITabBarController in the view-controller hierarchy reachable from `self`
    /// (children + presented), used to switch back to the Home tab when the flow was pushed.
    func dw_firstTabBarController() -> UITabBarController? {
        if let tab = self as? UITabBarController { return tab }
        for child in children {
            if let tab = child.dw_firstTabBarController() { return tab }
        }
        if let presented = presentedViewController {
            return presented.dw_firstTabBarController()
        }
        return nil
    }
}
