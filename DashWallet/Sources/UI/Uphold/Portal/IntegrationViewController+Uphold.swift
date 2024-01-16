//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation

extension IntegrationViewController: DWUpholdLogoutTutorialViewControllerDelegate {
    
    internal func getUpholdVcFor(operation: IntegrationItemType) -> UIViewController? {
        switch operation {
        case .buyDash:
            return createTopperWidget()
        case .transferDash:
            return createUpholdTransferController()
        default:
            return nil
        }
    }
    
    func onUpholdLogout() {
        let logoutTutorialController = DWUpholdLogoutTutorialViewController.controller()
        logoutTutorialController.delegate = self
        let alertController = DWAlertController(contentController: logoutTutorialController)
        alertController.setupActions(logoutTutorialController.providedActions)
        alertController.preferredAction = logoutTutorialController.preferredAction
        present(alertController, animated: true, completion: nil)
    }
    
    func upholdLogoutTutorialViewControllerDidCancel(_ controller: DWUpholdLogoutTutorialViewController) {
        controller.dismiss(animated: true)
    }
    
    func upholdLogoutTutorialViewControllerOpenUpholdWebsite(_ controller: DWUpholdLogoutTutorialViewController) {
        controller.dismiss(animated: true, completion: { [weak self] in
            guard let url = self?.model.logoutUrl else { return }
            self?.initAuthentication(url: url)
        })
    }
    
    private func createTopperWidget() -> UIViewController? {
        let urlString = TopperViewModel.shared.topperBuyUrl(walletName: Bundle.main.infoDictionary!["CFBundleDisplayName"] as! String)
        if let url = URL(string: urlString) {
            return SFSafariViewController.dw_controller(with: url)
        }
        
        return nil
    }
    
    private func createUpholdTransferController() -> UIViewController? {
        guard model.isLoggedIn else { return nil }
        guard let dashCard = (self.model as? UpholdPortalModel)?.dashCard else { return nil }
        
        let controller = UpholdTransferViewController.init(card: dashCard)
        controller.delegate = self
        controller.hidesBottomBarWhenPushed = true
        
        return controller
    }
}

extension IntegrationViewController: UpholdTransferViewControllerDelegate {
    func upholdTransferViewController(_ vc: UpholdTransferViewController, didSend transaction: DWUpholdTransactionObject) {
        navigationController?.popViewController(animated: true)

        let model = self.model as! UpholdPortalModel
        let alert = UIAlertController(title: NSLocalizedString("Uphold", comment: ""),
                                      message: model.successMessageText(for: transaction),
                                      preferredStyle: .alert)

        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                     style: .cancel,
                                     handler: nil)
        alert.addAction(okAction)

        let openAction = UIAlertAction(title: NSLocalizedString("See on Uphold", comment: ""),
                                       style: .default) { _ in
            if let url = model.transactionURL(for: transaction) {
                UIApplication.shared.open(url)
            }
        }
        alert.addAction(openAction)
        alert.preferredAction = openAction

        navigationController?.present(alert, animated: true, completion: nil)
    }
}
