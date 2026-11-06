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

extension UIViewController {
    /// Open the Dash DEX portal behind the spending authentication gate.
    ///
    /// The portal is a spending surface, so every entry point — the Home
    /// shortcut and the payments landing's swap card — goes through this one
    /// gate; a destination that asks for a PIN from one entry point and not
    /// another is not a gate at all.
    func presentDashDEXAfterAuthentication() {
        AuthenticationService.shared.authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            alertIfLockout: true
        ) { [weak self] authenticated, _, _ in
            guard authenticated, let self else { return }
            let controller = SwapKitPortalViewController()
            controller.hidesBottomBarWhenPushed = true
            let navigationController = BaseNavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .fullScreen
            self.present(navigationController, animated: true)
        }
    }
}

final class SwapKitPortalViewController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    private let flowCoordinator = SwapFlowCoordinator(swapProvider: SwapBackend.swapKit.makeProvider())

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.dw_secondaryBackground()

        let portalView = SwapKitPortalView(
            onBack: { [weak self] in
                guard let self else { return }
                if let nav = self.navigationController, nav.viewControllers.first !== self {
                    nav.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            },
            onBuyDash: { [weak self] in
                self?.flowCoordinator.start(in: self?.navigationController, direction: .buy)
            },
            onSellDash: { [weak self] in
                self?.flowCoordinator.start(in: self?.navigationController, direction: .sell)
            }
        )

        let hostingController = UIHostingController(rootView: portalView)
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
}
