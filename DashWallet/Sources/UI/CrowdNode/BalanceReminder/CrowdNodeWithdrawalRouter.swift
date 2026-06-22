//
//  Created by OpenAI Codex
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

import UIKit

@MainActor
enum CrowdNodeWithdrawalRouter {
    /// Returns true when navigation was started. Returns false when the flow was blocked
    /// and the user was shown an explanatory alert instead.
    @discardableResult
    static func openWithdrawal(from presenter: UIViewController) -> Bool {
        guard SyncingActivityMonitor.shared.state == .syncDone else {
            presentSyncingAlert(from: presenter)
            return false
        }

        CrowdNode.shared.restoreState()
        let state = CrowdNode.shared.signUpState

        guard state == .finished || state == .linkedOnline else {
            let rootViewController = CrowdNodeModelObjcWrapper.getRootVC()
            presentInNavigationController(rootViewController, from: presenter)
            return true
        }

        guard CrowdNodeModel.shared.canWithdraw else {
            presentMinimumBalanceError(from: presenter)
            return false
        }

        let portal = CrowdNodePortalController.controller()
        let navigationController = BaseNavigationController(rootViewController: portal)
        presenter.present(navigationController, animated: true) {
            navigationController.pushViewController(
                CrowdNodeTransferController.controller(mode: .withdraw),
                animated: false
            )
        }
        return true
    }

    private static func presentInNavigationController(_ rootViewController: UIViewController, from presenter: UIViewController) {
        let navigationController = BaseNavigationController(rootViewController: rootViewController)
        presenter.present(navigationController, animated: true)
    }

    private static func presentSyncingAlert(from presenter: UIViewController) {
        let title = NSLocalizedString("The chain is syncing…", comment: "")
        let message = NSLocalizedString("Wait until the chain is fully synced, so we can review your transaction history. Visit CrowdNode website to log in or sign up.", comment: "")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let websiteAction = UIAlertAction(
            title: NSLocalizedString("Go to CrowdNode website", comment: ""),
            style: .default
        ) { _ in
            UIApplication.shared.open(CrowdNodeObjcWrapper.crowdNodeWebsiteUrl(), options: [:], completionHandler: nil)
        }
        alert.addAction(websiteAction)

        let closeAction = UIAlertAction(
            title: NSLocalizedString("Close", comment: ""),
            style: .cancel
        )
        alert.addAction(closeAction)
        presenter.present(alert, animated: true)
    }

    private static func presentMinimumBalanceError(from presenter: UIViewController) {
        let controller = BasicInfoController()
        controller.icon = "image.crowdnode.error"
        controller.headerText = NSLocalizedString("You should have a positive balance on Dash Wallet", comment: "CrowdNode")
        controller.descriptionText = String.localizedStringWithFormat(
            NSLocalizedString("Deposit at least %@ Dash on your Dash Wallet to complete a withdrawal", comment: "CrowdNode"),
            CrowdNode.minimumLeftoverBalance.formattedDashAmountWithoutCurrencySymbol
        )
        controller.actionButtonText = CrowdNodeModel.shared.buyDashButtonText

        let navigationController = BaseNavigationController(rootViewController: controller)
        controller.mainAction = { [weak navigationController] in
            Task {
                if await CrowdNodeModel.shared.authenticate() {
                    let buySellController = BuySellPortalViewController.controller()
                    navigationController?.pushViewController(buySellController, animated: true)
                }
            }
        }

        presenter.present(navigationController, animated: true)
    }
}
